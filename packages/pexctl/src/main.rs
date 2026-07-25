use pexctl::{
    byte_differences, normalize_bdf, required_confirmation, sha256_hex,
    validate_sector0_replacement, verify_config_plan_directory, write_new_file, AtlasApplyPolicy,
    AtlasConfig, AtlasConfigPlanArtifact, AtlasConfigPlanManifest, Error, PlxSvcDevice, Result,
    SbrImage, StationLayout, ATLAS_CONFIG_PLAN_FILE, ATLAS_SPI_RECOVERY_REGION_SIZE,
    SBR_FLASH_OFFSET, SOC_END,
};
use serde::Serialize;
use std::env;
use std::fmt::Write as _;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

fn main() -> ExitCode {
    match run(env::args().skip(1).collect()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("pexctl: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run(args: Vec<String>) -> Result<()> {
    let Some(group) = args.first().map(String::as_str) else {
        print_help();
        return Ok(());
    };
    match group {
        "-h" | "--help" | "help" => {
            print_help();
            Ok(())
        }
        "-V" | "--version" | "version" => {
            println!("pexctl {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        "sbr" => run_sbr(&args[1..]),
        "flash" => run_flash(&args[1..]),
        "plan" => run_plan(&args[1..]),
        "device" => run_device(&args[1..]),
        other => Err(Error::Usage(format!(
            "unknown command {other:?}; run `pexctl help`"
        ))),
    }
}

fn run_sbr(args: &[String]) -> Result<()> {
    let Some(command) = args.first().map(String::as_str) else {
        return Err(Error::Usage(
            "missing SBR command; run `pexctl help`".into(),
        ));
    };
    match command {
        "inspect" | "topology" => {
            let json = optional_json_flag(args, 2, "pexctl sbr inspect IMAGE [--json]")?;
            let image = SbrImage::read(Path::new(&args[1]))?;
            if json {
                print_json(&image.inspection())?;
            } else {
                print_inspection(&image);
            }
            if !image.checksum_valid() {
                return Err(Error::Format("hardware checksum is invalid".into()));
            }
            Ok(())
        }
        "validate" => {
            expect_len(args, 2, "pexctl sbr validate IMAGE")?;
            let image = SbrImage::read(Path::new(&args[1]))?;
            image.validate()?;
            println!(
                "valid PEX88096 SBR: {} bytes, checksum {:#04x} at {:#x}",
                image.bytes().len(),
                image.expected_checksum(),
                image.checksum_offset()
            );
            Ok(())
        }
        "fields" => {
            let json = optional_json_flag(args, 2, "pexctl sbr fields IMAGE [--json]")?;
            let image = SbrImage::read(Path::new(&args[1]))?;
            image.validate()?;
            let inspection = image.soc_field_inspection();
            if json {
                print_json(&inspection)
            } else {
                print_named_fields(&inspection);
                Ok(())
            }
        }
        "entries" => run_sbr_entries(&args[1..]),
        "psw" => run_sbr_psw(&args[1..]),
        "ports" => run_sbr_ports(&args[1..]),
        "export-field-patch" => run_export_field_patch(&args[1..]),
        "export-entry-patch" => run_export_entry_patch(&args[1..]),
        "diff" => {
            let json = optional_json_flag(args, 3, "pexctl sbr diff BEFORE AFTER [--json]")?;
            let before = SbrImage::read(Path::new(&args[1]))?;
            let after = SbrImage::read(Path::new(&args[2]))?;
            if json {
                print_json(&before.diff(&after))?;
            } else {
                print_diff(&before, &after);
            }
            Ok(())
        }
        "export-config" => run_export_config(&args[1..]),
        "apply-config" => run_apply_config(&args[1..]),
        "set-station" => run_set_station(&args[1..]),
        "repair-checksum" => run_repair_checksum(&args[1..]),
        other => Err(Error::Usage(format!("unknown SBR command {other:?}"))),
    }
}

fn run_export_field_patch(args: &[String]) -> Result<()> {
    let usage =
        "pexctl sbr export-field-patch IMAGE --field NAME --value VALUE --output CONFIG.json";
    if args.is_empty()
        || args
            .iter()
            .take_while(|argument| !argument.starts_with("--"))
            .count()
            != 1
    {
        return Err(Error::Usage(format!("usage: {usage}")));
    }
    let field = option_value(args, "--field")?;
    let value = u8::try_from(parse_number(option_value(args, "--value")?)?)
        .map_err(|_| Error::Usage("--value exceeds 8 bits".into()))?;
    let output = PathBuf::from(option_value(args, "--output")?);
    reject_unknown_options(args, &["--field", "--value", "--output"])?;

    let image = SbrImage::read(Path::new(&args[0]))?;
    let config = image.expert_soc_field_config(field, value)?;
    write_new_file(&output, &config.to_json_pretty()?)?;
    println!(
        "wrote expert SoC field patch for {field} in {} to {}; applying it requires --allow-expert-fields",
        args[0],
        output.display()
    );
    Ok(())
}

fn run_export_entry_patch(args: &[String]) -> Result<()> {
    let usage = "pexctl sbr export-entry-patch IMAGE --block psb|psb-serdes --index N --value VALUE --output CONFIG.json";
    if args.is_empty()
        || args
            .iter()
            .take_while(|argument| !argument.starts_with("--"))
            .count()
            != 1
    {
        return Err(Error::Usage(format!("usage: {usage}")));
    }
    let block = option_value(args, "--block")?;
    let index = usize::try_from(parse_number(option_value(args, "--index")?)?)
        .map_err(|_| Error::Usage("--index does not fit host address space".into()))?;
    let value = u32::try_from(parse_number(option_value(args, "--value")?)?)
        .map_err(|_| Error::Usage("--value exceeds 32 bits".into()))?;
    let output = PathBuf::from(option_value(args, "--output")?);
    reject_unknown_options(args, &["--block", "--index", "--value", "--output"])?;

    let image = SbrImage::read(Path::new(&args[0]))?;
    let config = match block {
        "psb" => image.expert_psb_entry_config(index, value)?,
        "psb-serdes" => image.expert_psb_serdes_entry_config(index, value)?,
        _ => {
            return Err(Error::Usage(format!(
                "unsupported entry block {block:?}; expected psb or psb-serdes"
            )));
        }
    };
    write_new_file(&output, &config.to_json_pretty()?)?;
    println!(
        "wrote expert {block} entry {index} patch for {} to {}; applying it requires --allow-expert-entries",
        args[0],
        output.display()
    );
    Ok(())
}

fn run_sbr_entries(args: &[String]) -> Result<()> {
    let usage = "pexctl sbr entries IMAGE [--block psb|psb-serdes] [--json]";
    if args.is_empty()
        || args
            .iter()
            .take_while(|argument| !argument.starts_with("--"))
            .count()
            != 1
    {
        return Err(Error::Usage(format!("usage: {usage}")));
    }
    reject_unknown_options_and_flags(args, &["--block"], &["--json"])?;
    let block = if args.iter().any(|argument| argument == "--block") {
        Some(option_value(args, "--block")?)
    } else {
        None
    };
    let image = SbrImage::read(Path::new(&args[0]))?;
    image.validate()?;
    let inspection = filtered_entry_inspection(&image, block)?;
    if args.iter().any(|argument| argument == "--json") {
        print_json(&inspection)
    } else {
        print_entry_inspection(&inspection);
        Ok(())
    }
}

fn run_sbr_psw(args: &[String]) -> Result<()> {
    let usage = "pexctl sbr psw IMAGE [--block psw0|psw1|psw2|psw3|psw4|psw5|pswx2] [--json]";
    if args.is_empty()
        || args
            .iter()
            .take_while(|argument| !argument.starts_with("--"))
            .count()
            != 1
    {
        return Err(Error::Usage(format!("usage: {usage}")));
    }
    reject_unknown_options_and_flags(args, &["--block"], &["--json"])?;
    let block = if args.iter().any(|argument| argument == "--block") {
        Some(option_value(args, "--block")?)
    } else {
        None
    };
    let image = SbrImage::read(Path::new(&args[0]))?;
    image.validate()?;
    let inspection = filtered_psw_inspection(&image, block)?;
    if args.iter().any(|argument| argument == "--json") {
        print_json(&inspection)
    } else {
        print_psw_inspection(&inspection);
        Ok(())
    }
}

fn run_sbr_ports(args: &[String]) -> Result<()> {
    let usage = "pexctl sbr ports IMAGE [--port N] [--json]";
    if args.is_empty()
        || args
            .iter()
            .take_while(|argument| !argument.starts_with("--"))
            .count()
            != 1
    {
        return Err(Error::Usage(format!("usage: {usage}")));
    }
    reject_unknown_options_and_flags(args, &["--port"], &["--json"])?;
    let port = optional_u8(args, "--port")?;
    let image = SbrImage::read(Path::new(&args[0]))?;
    image.validate()?;
    let inspection = filtered_port_defaults_inspection(&image, port)?;
    if args.iter().any(|argument| argument == "--json") {
        print_json(&inspection)
    } else {
        print_port_defaults_inspection(&inspection);
        Ok(())
    }
}

fn run_export_config(args: &[String]) -> Result<()> {
    if args.is_empty() {
        return Err(Error::Usage(
            "usage: pexctl sbr export-config IMAGE --output CONFIG.json".into(),
        ));
    }
    let input = PathBuf::from(&args[0]);
    let output = PathBuf::from(option_value(args, "--output")?);
    reject_unknown_options(args, &["--output"])?;
    let image = SbrImage::read(&input)?;
    image.validate()?;
    let config = image.editable_config();
    let bytes = config.to_json_pretty()?;
    write_new_file(&output, &bytes)?;
    let unclassified = config
        .stations
        .iter()
        .filter(|entry| entry.layout.is_none())
        .count();
    println!(
        "wrote editable Atlas configuration for {} to {}",
        input.display(),
        output.display()
    );
    if unclassified != 0 {
        println!(
            "{unclassified} station layout(s) are unclassified and exported without a layout; applying this file preserves them"
        );
    }
    Ok(())
}

fn run_apply_config(args: &[String]) -> Result<()> {
    if args.len() < 2 {
        return Err(Error::Usage(
            "usage: pexctl sbr apply-config INPUT CONFIG.json --output OUTPUT [--allow-expert-fields] [--allow-expert-entries]".into(),
        ));
    }
    let input = PathBuf::from(&args[0]);
    let config_path = PathBuf::from(&args[1]);
    let output = PathBuf::from(option_value(args, "--output")?);
    let allow_expert_fields = args
        .iter()
        .any(|argument| argument == "--allow-expert-fields");
    let allow_expert_entries = args
        .iter()
        .any(|argument| argument == "--allow-expert-entries");
    reject_unknown_options_and_flags(
        args,
        &["--output"],
        &["--allow-expert-fields", "--allow-expert-entries"],
    )?;
    let policy = AtlasApplyPolicy {
        allow_expert_soc_fields: allow_expert_fields,
        allow_expert_entries,
    };
    let config = AtlasConfig::read(&config_path)?;
    config.validate_with_policy(policy)?;

    let mut image = SbrImage::read(&input)?;
    image.validate()?;
    let before = image.clone();
    image.apply_config_with_options(&config, policy)?;
    let differences = byte_differences(before.bytes(), image.bytes());
    if differences.is_empty() {
        return Err(Error::Safety(
            "configuration already matches the input SBR; no output written".into(),
        ));
    }
    write_new_file(&output, image.bytes())?;
    println!(
        "wrote {} by applying {} to {}; {} bytes changed",
        output.display(),
        config_path.display(),
        input.display(),
        differences.len()
    );
    print_diff(&before, &image);
    Ok(())
}

fn run_set_station(args: &[String]) -> Result<()> {
    if args.is_empty() {
        return Err(Error::Usage(
            "usage: pexctl sbr set-station INPUT --station N --layout LAYOUT --output OUTPUT"
                .into(),
        ));
    }
    let input = PathBuf::from(&args[0]);
    let station = option_value(args, "--station")?
        .parse::<usize>()
        .map_err(|_| Error::Usage("--station must be an integer from 0 through 5".into()))?;
    let layout = StationLayout::parse(option_value(args, "--layout")?)?;
    let output = PathBuf::from(option_value(args, "--output")?);
    reject_unknown_options(args, &["--station", "--layout", "--output"])?;

    let mut image = SbrImage::read(&input)?;
    image.validate()?;
    let before = image.clone();
    let old_codes = image.station_codes(station)?;
    image.set_station_layout(station, layout)?;
    image.validate()?;
    let new_codes = image.station_codes(station)?;
    let differences = byte_differences(before.bytes(), image.bytes());
    if differences.is_empty() {
        return Err(Error::Safety(format!(
            "station {station} already has layout {layout}; no output written"
        )));
    }
    write_new_file(&output, image.bytes())?;
    println!(
        "wrote {}: station {} {:?} -> {:?} ({layout}); {} bytes changed",
        output.display(),
        station,
        old_codes,
        new_codes,
        differences.len()
    );
    for difference in differences {
        println!(
            "  {:#06x}: {:02x} -> {:02x}",
            difference.offset, difference.before, difference.after
        );
    }
    Ok(())
}

fn run_repair_checksum(args: &[String]) -> Result<()> {
    if args.is_empty() {
        return Err(Error::Usage(
            "usage: pexctl sbr repair-checksum INPUT --output OUTPUT".into(),
        ));
    }
    let input = PathBuf::from(&args[0]);
    let output = PathBuf::from(option_value(args, "--output")?);
    reject_unknown_options(args, &["--output"])?;
    let mut image = SbrImage::read(&input)?;
    let before = image.stored_checksum();
    image.update_checksum();
    image.validate()?;
    if before == image.stored_checksum() {
        return Err(Error::Safety(
            "checksum is already valid; no output written".into(),
        ));
    }
    write_new_file(&output, image.bytes())?;
    println!(
        "wrote {}: checksum {before:#010x} -> {:#010x}",
        output.display(),
        image.stored_checksum()
    );
    Ok(())
}

fn run_flash(args: &[String]) -> Result<()> {
    let Some(command) = args.first().map(String::as_str) else {
        return Err(Error::Usage(
            "missing flash command; run `pexctl help`".into(),
        ));
    };
    match command {
        "extract-sbr" => run_extract_sbr(&args[1..]),
        "replace-sbr" => run_replace_sbr(&args[1..]),
        other => Err(Error::Usage(format!("unknown flash command {other:?}"))),
    }
}

fn run_extract_sbr(args: &[String]) -> Result<()> {
    if args.is_empty() {
        return Err(Error::Usage(
            "usage: pexctl flash extract-sbr FLASH --output OUTPUT [--offset 0x400]".into(),
        ));
    }
    let input = PathBuf::from(&args[0]);
    let output = PathBuf::from(option_value(args, "--output")?);
    let offset = optional_number(args, "--offset")?.unwrap_or(SBR_FLASH_OFFSET);
    reject_unknown_options(args, &["--output", "--offset"])?;
    let flash = fs::read(&input)
        .map_err(|source| Error::io(format!("reading {}", input.display()), source))?;
    let offset = usize::try_from(offset)
        .map_err(|_| Error::Usage("flash offset does not fit host address space".into()))?;
    let prefix = flash
        .get(offset..)
        .ok_or_else(|| Error::Format(format!("flash ends before SBR offset {offset:#x}")))?;
    let image = SbrImage::parse_prefix(prefix)?;
    image.validate()?;
    write_new_file(&output, image.bytes())?;
    println!(
        "extracted valid {}-byte SBR at {offset:#x} to {}",
        image.bytes().len(),
        output.display()
    );
    Ok(())
}

fn run_replace_sbr(args: &[String]) -> Result<()> {
    if args.len() < 2 {
        return Err(Error::Usage(
            "usage: pexctl flash replace-sbr FLASH SBR --output OUTPUT [--offset 0x400]".into(),
        ));
    }
    let flash_path = PathBuf::from(&args[0]);
    let sbr_path = PathBuf::from(&args[1]);
    let output = PathBuf::from(option_value(args, "--output")?);
    let offset = optional_number(args, "--offset")?.unwrap_or(SBR_FLASH_OFFSET);
    reject_unknown_options(args, &["--output", "--offset"])?;

    let mut flash = fs::read(&flash_path)
        .map_err(|source| Error::io(format!("reading {}", flash_path.display()), source))?;
    let candidate = SbrImage::read(&sbr_path)?;
    candidate.validate()?;
    let offset = usize::try_from(offset)
        .map_err(|_| Error::Usage("flash offset does not fit host address space".into()))?;
    let current_prefix = flash
        .get(offset..)
        .ok_or_else(|| Error::Format(format!("flash ends before SBR offset {offset:#x}")))?;
    let current = SbrImage::parse_prefix(current_prefix)?;
    current.validate()?;
    let end = offset
        .checked_add(candidate.bytes().len())
        .ok_or_else(|| Error::Usage("replacement range overflow".into()))?;
    if end > flash.len() {
        return Err(Error::Safety(format!(
            "candidate ends at {end:#x}, beyond flash image length {:#x}",
            flash.len()
        )));
    }
    if current.bytes().len() != candidate.bytes().len() {
        return Err(Error::Safety(format!(
            "candidate length {:#x} differs from current SBR length {:#x}; variable-length replacement is not yet proven safe",
            candidate.bytes().len(),
            current.bytes().len()
        )));
    }
    flash[offset..end].copy_from_slice(candidate.bytes());
    write_new_file(&output, &flash)?;
    println!(
        "wrote sector-preserving flash candidate {} with {}-byte SBR replaced at {offset:#x}",
        output.display(),
        candidate.bytes().len()
    );
    Ok(())
}

fn run_plan(args: &[String]) -> Result<()> {
    let Some(command) = args.first().map(String::as_str) else {
        return Err(Error::Usage(
            "missing plan command; run `pexctl help`".into(),
        ));
    };
    match command {
        "verify" => {
            let json = optional_json_flag(args, 2, "pexctl plan verify DIRECTORY [--json]")?;
            let plan = verify_config_plan_directory(Path::new(&args[1]))?;
            if json {
                print_json(plan.manifest())
            } else {
                let manifest = plan.manifest();
                println!("valid Atlas configuration plan: {}", args[1]);
                println!(
                    "device: {} {:04x}:{:04x}, SPI CS0 {:02x} {:02x} {:02x}",
                    manifest.bdf,
                    manifest.pci_vendor,
                    manifest.pci_device,
                    manifest.jedec_id[0],
                    manifest.jedec_id[1],
                    manifest.jedec_id[2]
                );
                println!(
                    "flash: {:#x} bytes, SBR: {:#x} bytes at {:#x}",
                    manifest.flash_size, manifest.sbr_size, manifest.sbr_offset
                );
                println!(
                    "verified {} hashes plus complete backup, region, SBR, configuration, inspection, and diff relationships",
                    manifest.artifacts.len()
                );
                println!(
                    "required write confirmation: {}",
                    manifest.required_confirmation
                );
                Ok(())
            }
        }
        other => Err(Error::Usage(format!("unknown plan command {other:?}"))),
    }
}

fn run_device(args: &[String]) -> Result<()> {
    let Some(command) = args.first().map(String::as_str) else {
        return Err(Error::Usage(
            "missing device command; run `pexctl help`".into(),
        ));
    };
    match command {
        "spi-id" => {
            let options = &args[1..];
            let bdf = option_value(options, "--bdf")?;
            reject_unknown_options(options, &["--bdf"])?;
            let device = PlxSvcDevice::open(bdf)?;
            let identity = device.spi_identity()?;
            println!(
                "{} SPI CS0 JEDEC ID: {:02x} {:02x} {:02x}",
                device.bdf(),
                identity[0],
                identity[1],
                identity[2]
            );
            Ok(())
        }
        "backup-flash" => {
            let options = &args[1..];
            let bdf = option_value(options, "--bdf")?;
            let output = PathBuf::from(option_value(options, "--output")?);
            reject_unknown_options(options, &["--bdf", "--output"])?;
            let device = PlxSvcDevice::open(bdf)?;
            eprintln!(
                "pexctl: reading complete {} CS0 flash (mapped window, then serial tail)",
                device.bdf()
            );
            let bytes = device.read_complete_flash()?;
            write_new_file(&output, &bytes)?;
            println!(
                "read complete {}-byte CS0 flash from {} into {}",
                bytes.len(),
                device.bdf(),
                output.display()
            );
            Ok(())
        }
        "read-flash" => {
            let options = &args[1..];
            let bdf = option_value(options, "--bdf")?;
            let output = PathBuf::from(option_value(options, "--output")?);
            let offset = optional_number(options, "--offset")?.unwrap_or(0);
            let size = usize::try_from(parse_number(option_value(options, "--size")?)?)
                .map_err(|_| Error::Usage("--size does not fit host address space".into()))?;
            let method = if options.iter().any(|argument| argument == "--method") {
                option_value(options, "--method")?
            } else {
                "mapped"
            };
            reject_unknown_options(
                options,
                &["--bdf", "--output", "--offset", "--size", "--method"],
            )?;
            let device = PlxSvcDevice::open(bdf)?;
            let bytes = match method {
                "mapped" => device.read_flash_mapped(offset, size)?,
                "serial" => device.read_flash_serial(offset, size)?,
                _ => {
                    return Err(Error::Usage(format!(
                        "unsupported flash read method {method:?}; expected mapped or serial"
                    )));
                }
            };
            write_new_file(&output, &bytes)?;
            println!(
                "read {size} bytes from {} ({:04x}:{:04x}) through the PlxSvc {method} CS0 path at flash offset {offset:#x} into {}",
                device.bdf(),
                device.vendor(),
                device.device(),
                output.display()
            );
            if method == "mapped" {
                println!(
                    "BAR0 safely exposes {:#x} bytes before the port-register overlap",
                    device.mapped_flash_size()
                );
            }
            Ok(())
        }
        "read-sbr" => {
            let bdf = option_value(&args[1..], "--bdf")?;
            let output = PathBuf::from(option_value(&args[1..], "--output")?);
            let offset = optional_number(&args[1..], "--offset")?.unwrap_or(SBR_FLASH_OFFSET);
            reject_unknown_options(&args[1..], &["--bdf", "--output", "--offset"])?;
            let device = PlxSvcDevice::open(bdf)?;
            let image = device.read_sbr(offset)?;
            image.validate()?;
            write_new_file(&output, image.bytes())?;
            println!(
                "read valid {}-byte SBR from {} ({:04x}:{:04x}) through PlxSvc at flash offset {offset:#x} into {}",
                image.bytes().len(),
                device.bdf(),
                device.vendor(),
                device.device(),
                output.display()
            );
            Ok(())
        }
        "inspect-sbr" => {
            let options = &args[1..];
            let bdf = option_value(options, "--bdf")?;
            let offset = optional_number(options, "--offset")?.unwrap_or(SBR_FLASH_OFFSET);
            let json = options.iter().any(|argument| argument == "--json");
            reject_unknown_options_and_flags(options, &["--bdf", "--offset"], &["--json"])?;
            let device = PlxSvcDevice::open(bdf)?;
            let image = device.read_sbr(offset)?;
            image.validate()?;
            eprintln!(
                "pexctl: read valid {}-byte SBR from {} at flash offset {offset:#x}",
                image.bytes().len(),
                device.bdf()
            );
            if json {
                print_json(&image.inspection())
            } else {
                print_inspection(&image);
                Ok(())
            }
        }
        "entries" => run_device_entries(&args[1..]),
        "fields" => run_device_fields(&args[1..]),
        "psw" => run_device_psw(&args[1..]),
        "ports" => run_device_ports(&args[1..]),
        "prepare-station" => run_prepare_station(&args[1..]),
        "prepare-config" => run_prepare_config(&args[1..]),
        "program-plan" => {
            let options = &args[1..];
            let bdf = normalize_bdf(option_value(options, "--bdf")?)?;
            let plan_dir = PathBuf::from(option_value(options, "--plan-dir")?);
            let confirmation = option_value(options, "--confirm")?;
            let allow_expert_fields = options
                .iter()
                .any(|argument| argument == "--allow-expert-fields");
            let allow_expert_entries = options
                .iter()
                .any(|argument| argument == "--allow-expert-entries");
            reject_unknown_options_and_flags(
                options,
                &["--bdf", "--plan-dir", "--confirm"],
                &["--allow-expert-fields", "--allow-expert-entries"],
            )?;
            let required_confirmation = required_confirmation(&bdf)?;
            if confirmation != required_confirmation {
                return Err(Error::Safety(format!(
                    "confirmation mismatch; this operation requires --confirm {required_confirmation:?}"
                )));
            }

            let plan = verify_config_plan_directory(&plan_dir)?;
            let manifest = plan.manifest();
            if manifest.policy.allow_expert_soc_fields && !allow_expert_fields {
                return Err(Error::Safety(
                    "plan was prepared with expert SoC fields enabled; pass --allow-expert-fields again at programming time"
                        .into(),
                ));
            }
            if manifest.policy.allow_expert_entries && !allow_expert_entries {
                return Err(Error::Safety(
                    "plan was prepared with expert indexed records enabled; pass --allow-expert-entries again at programming time"
                        .into(),
                ));
            }
            if manifest.bdf != bdf {
                return Err(Error::Safety(format!(
                    "plan is bound to {}, not requested device {bdf}",
                    manifest.bdf
                )));
            }
            let device = PlxSvcDevice::open(&bdf)?;
            if (device.vendor(), device.device()) != (manifest.pci_vendor, manifest.pci_device) {
                return Err(Error::Safety(format!(
                    "live PCI identity {:04x}:{:04x} differs from plan identity {:04x}:{:04x}",
                    device.vendor(),
                    device.device(),
                    manifest.pci_vendor,
                    manifest.pci_device
                )));
            }
            eprintln!(
                "pexctl: confirmation and complete plan accepted; checking live bytes, then erasing, programming, and verifying {} CS0 sector 0",
                device.bdf()
            );
            device.program_sector0_recovery_gated(
                plan.expected_current(),
                plan.candidate(),
                confirmation,
            )?;
            println!(
                "programmed plan {} and read-back verified {} CS0 sector 0; no reset was issued",
                plan_dir.display(),
                device.bdf()
            );
            Ok(())
        }
        "program-sector0" => {
            let options = &args[1..];
            let bdf = normalize_bdf(option_value(options, "--bdf")?)?;
            let expected_path = PathBuf::from(option_value(options, "--expected-current")?);
            let candidate_path = PathBuf::from(option_value(options, "--candidate")?);
            let confirmation = option_value(options, "--confirm")?;
            reject_unknown_options(
                options,
                &["--bdf", "--expected-current", "--candidate", "--confirm"],
            )?;
            let required_confirmation = required_confirmation(&bdf)?;
            if confirmation != required_confirmation {
                return Err(Error::Safety(format!(
                    "confirmation mismatch; this operation requires --confirm {required_confirmation:?}"
                )));
            }
            let expected = fs::read(&expected_path).map_err(|source| {
                Error::io(format!("reading {}", expected_path.display()), source)
            })?;
            let candidate = fs::read(&candidate_path).map_err(|source| {
                Error::io(format!("reading {}", candidate_path.display()), source)
            })?;
            validate_sector0_replacement(&expected, &candidate)?;
            let device = PlxSvcDevice::open(&bdf)?;
            eprintln!(
                "pexctl: confirmation accepted; checking live bytes, then erasing, programming, and verifying {} CS0 sector 0",
                device.bdf()
            );
            device.program_sector0_recovery_gated(&expected, &candidate, confirmation)?;
            println!(
                "programmed and read-back verified {} CS0 sector 0; no reset was issued",
                device.bdf()
            );
            Ok(())
        }
        other => Err(Error::Usage(format!("unknown device command {other:?}"))),
    }
}

fn run_device_entries(options: &[String]) -> Result<()> {
    let bdf = option_value(options, "--bdf")?;
    let offset = optional_number(options, "--offset")?.unwrap_or(SBR_FLASH_OFFSET);
    let block = if options.iter().any(|argument| argument == "--block") {
        Some(option_value(options, "--block")?)
    } else {
        None
    };
    let json = options.iter().any(|argument| argument == "--json");
    reject_unknown_options_and_flags(options, &["--bdf", "--offset", "--block"], &["--json"])?;

    let device = PlxSvcDevice::open(bdf)?;
    let image = device.read_sbr(offset)?;
    image.validate()?;
    let inspection = filtered_entry_inspection(&image, block)?;
    eprintln!(
        "pexctl: read valid {}-byte SBR from {} at flash offset {offset:#x}",
        image.bytes().len(),
        device.bdf()
    );
    if json {
        print_json(&inspection)
    } else {
        print_entry_inspection(&inspection);
        Ok(())
    }
}

fn run_device_fields(options: &[String]) -> Result<()> {
    let bdf = option_value(options, "--bdf")?;
    let offset = optional_number(options, "--offset")?.unwrap_or(SBR_FLASH_OFFSET);
    let json = options.iter().any(|argument| argument == "--json");
    reject_unknown_options_and_flags(options, &["--bdf", "--offset"], &["--json"])?;

    let device = PlxSvcDevice::open(bdf)?;
    let image = device.read_sbr(offset)?;
    image.validate()?;
    let inspection = image.soc_field_inspection();
    eprintln!(
        "pexctl: read valid {}-byte SBR from {} at flash offset {offset:#x}",
        image.bytes().len(),
        device.bdf()
    );
    if json {
        print_json(&inspection)
    } else {
        print_named_fields(&inspection);
        Ok(())
    }
}

fn run_device_psw(options: &[String]) -> Result<()> {
    let bdf = option_value(options, "--bdf")?;
    let offset = optional_number(options, "--offset")?.unwrap_or(SBR_FLASH_OFFSET);
    let block = if options.iter().any(|argument| argument == "--block") {
        Some(option_value(options, "--block")?)
    } else {
        None
    };
    let json = options.iter().any(|argument| argument == "--json");
    reject_unknown_options_and_flags(options, &["--bdf", "--offset", "--block"], &["--json"])?;

    let device = PlxSvcDevice::open(bdf)?;
    let image = device.read_sbr(offset)?;
    image.validate()?;
    let inspection = filtered_psw_inspection(&image, block)?;
    eprintln!(
        "pexctl: read valid {}-byte SBR from {} at flash offset {offset:#x}",
        image.bytes().len(),
        device.bdf()
    );
    if json {
        print_json(&inspection)
    } else {
        print_psw_inspection(&inspection);
        Ok(())
    }
}

fn run_device_ports(options: &[String]) -> Result<()> {
    let bdf = option_value(options, "--bdf")?;
    let offset = optional_number(options, "--offset")?.unwrap_or(SBR_FLASH_OFFSET);
    let port = optional_u8(options, "--port")?;
    let json = options.iter().any(|argument| argument == "--json");
    reject_unknown_options_and_flags(options, &["--bdf", "--offset", "--port"], &["--json"])?;

    let device = PlxSvcDevice::open(bdf)?;
    let image = device.read_sbr(offset)?;
    image.validate()?;
    let inspection = filtered_port_defaults_inspection(&image, port)?;
    eprintln!(
        "pexctl: read valid {}-byte SBR from {} at flash offset {offset:#x}",
        image.bytes().len(),
        device.bdf()
    );
    if json {
        print_json(&inspection)
    } else {
        print_port_defaults_inspection(&inspection);
        Ok(())
    }
}

fn filtered_entry_inspection(
    image: &SbrImage,
    block: Option<&str>,
) -> Result<pexctl::SbrEntryInspection> {
    let mut inspection = image.entry_inspection();
    match block {
        Some("psb") => inspection.psb_serdes_entries.clear(),
        Some("psb-serdes") => inspection.psb_entries.clear(),
        Some(block) => {
            return Err(Error::Usage(format!(
                "unsupported entry block {block:?}; expected psb or psb-serdes"
            )));
        }
        None => {}
    }
    Ok(inspection)
}

fn filtered_psw_inspection(image: &SbrImage, block: Option<&str>) -> Result<pexctl::PswInspection> {
    let mut inspection = image.psw_inspection();
    if let Some(block) = block {
        if !matches!(
            block,
            "psw0" | "psw1" | "psw2" | "psw3" | "psw4" | "psw5" | "pswx2"
        ) {
            return Err(Error::Usage(format!(
                "unsupported PSW block {block:?}; expected psw0, psw1, psw2, psw3, psw4, psw5, or pswx2"
            )));
        }
        inspection.blocks.retain(|entry| entry.block == block);
    }
    Ok(inspection)
}

fn filtered_port_defaults_inspection(
    image: &SbrImage,
    port: Option<u8>,
) -> Result<pexctl::PortDefaultsInspection> {
    let mut inspection = image.port_defaults_inspection();
    if let Some(port) = port {
        if !matches!(port, 0..=95 | 116 | 117) {
            return Err(Error::Usage(format!(
                "unsupported Atlas port {port}; expected 0 through 95, 116, or 117"
            )));
        }
        inspection.ports.retain(|entry| entry.port == port);
    }
    Ok(inspection)
}

fn run_prepare_station(options: &[String]) -> Result<()> {
    let bdf = option_value(options, "--bdf")?;
    let station = option_value(options, "--station")?
        .parse::<u8>()
        .map_err(|_| Error::Usage("--station must be an integer from 0 through 5".into()))?;
    let layout = StationLayout::parse(option_value(options, "--layout")?)?;
    let output_dir = PathBuf::from(option_value(options, "--output-dir")?);
    reject_unknown_options(options, &["--bdf", "--station", "--layout", "--output-dir"])?;
    let config = AtlasConfig::station_layout(station, layout)?;
    prepare_config_plan(bdf, &config, &output_dir, AtlasApplyPolicy::default())
}

fn run_prepare_config(options: &[String]) -> Result<()> {
    let bdf = option_value(options, "--bdf")?;
    let config_path = PathBuf::from(option_value(options, "--config")?);
    let output_dir = PathBuf::from(option_value(options, "--output-dir")?);
    let allow_expert_fields = options
        .iter()
        .any(|argument| argument == "--allow-expert-fields");
    let allow_expert_entries = options
        .iter()
        .any(|argument| argument == "--allow-expert-entries");
    reject_unknown_options_and_flags(
        options,
        &["--bdf", "--config", "--output-dir"],
        &["--allow-expert-fields", "--allow-expert-entries"],
    )?;
    let config = AtlasConfig::read(&config_path)?;
    prepare_config_plan(
        bdf,
        &config,
        &output_dir,
        AtlasApplyPolicy {
            allow_expert_soc_fields: allow_expert_fields,
            allow_expert_entries,
        },
    )
}

fn prepare_config_plan(
    bdf: &str,
    config: &AtlasConfig,
    output_dir: &Path,
    policy: AtlasApplyPolicy,
) -> Result<()> {
    config.validate_with_policy(policy)?;
    if output_dir.exists() {
        return Err(Error::Safety(format!(
            "{} already exists; choose a new plan directory",
            output_dir.display()
        )));
    }

    let device = PlxSvcDevice::open(bdf)?;
    let identity = device.spi_identity()?;
    eprintln!(
        "pexctl: pass 1/2: reading complete {} CS0 flash",
        device.bdf()
    );
    let flash_a = device.read_complete_flash()?;
    eprintln!(
        "pexctl: pass 2/2: reading complete {} CS0 flash",
        device.bdf()
    );
    let flash_b = device.read_complete_flash()?;
    if flash_a != flash_b {
        let first = flash_a
            .iter()
            .zip(&flash_b)
            .position(|(left, right)| left != right)
            .or_else(|| {
                (flash_a.len() != flash_b.len()).then_some(flash_a.len().min(flash_b.len()))
            });
        return Err(Error::Safety(format!(
            "complete flash passes differ{}; no plan directory was created",
            first
                .map(|offset| format!(" (first mismatch at {offset:#x})"))
                .unwrap_or_default()
        )));
    }
    if flash_a.len() < ATLAS_SPI_RECOVERY_REGION_SIZE {
        return Err(Error::Safety(format!(
            "complete flash is only {:#x} bytes, shorter than the {ATLAS_SPI_RECOVERY_REGION_SIZE:#x}-byte recovery region",
            flash_a.len()
        )));
    }

    let sbr_offset = usize::try_from(SBR_FLASH_OFFSET)
        .map_err(|_| Error::Usage("SBR offset does not fit host address space".into()))?;
    let current_sbr = SbrImage::parse_prefix(
        flash_a
            .get(sbr_offset..)
            .ok_or_else(|| Error::Format("complete flash ends before the SBR".into()))?,
    )?;
    current_sbr.validate()?;

    let mut candidate_sbr = current_sbr.clone();
    candidate_sbr.apply_config_with_options(config, policy)?;
    candidate_sbr.validate()?;
    let report = current_sbr.diff(&candidate_sbr);
    let sbr_differences = byte_differences(current_sbr.bytes(), candidate_sbr.bytes());
    if sbr_differences.is_empty() {
        return Err(Error::Safety(
            "configuration already matches the live SBR; no plan directory was created".into(),
        ));
    }

    let current_region = flash_a[..ATLAS_SPI_RECOVERY_REGION_SIZE].to_vec();
    let mut candidate_region = current_region.clone();
    let sbr_end = sbr_offset
        .checked_add(candidate_sbr.bytes().len())
        .ok_or_else(|| Error::Usage("candidate SBR range overflow".into()))?;
    candidate_region[sbr_offset..sbr_end].copy_from_slice(candidate_sbr.bytes());
    validate_sector0_replacement(&current_region, &candidate_region)?;

    let required_confirmation = required_confirmation(device.bdf())?;
    let config_json = config.to_json_pretty()?;
    let current_inspection_json = json_bytes(&current_sbr.inspection())?;
    let candidate_inspection_json = json_bytes(&candidate_sbr.inspection())?;
    let diff_json = json_bytes(&report)?;
    let files = [
        ("current-flash-a.bin", flash_a.as_slice()),
        ("current-flash-b.bin", flash_b.as_slice()),
        ("current-region.bin", current_region.as_slice()),
        ("current-sbr.bin", current_sbr.bytes()),
        ("candidate-region.bin", candidate_region.as_slice()),
        ("candidate-sbr.bin", candidate_sbr.bytes()),
        ("applied-config.json", config_json.as_slice()),
        (
            "current-inspection.json",
            current_inspection_json.as_slice(),
        ),
        (
            "candidate-inspection.json",
            candidate_inspection_json.as_slice(),
        ),
        ("diff.json", diff_json.as_slice()),
    ];
    let mut manifest = String::new();
    writeln!(manifest, "format: pexctl-config-plan-v1").expect("writing to String");
    writeln!(manifest, "bdf: {}", device.bdf()).expect("writing to String");
    writeln!(
        manifest,
        "pci-id: {:04x}:{:04x}",
        device.vendor(),
        device.device()
    )
    .expect("writing to String");
    writeln!(
        manifest,
        "jedec-id: {:02x} {:02x} {:02x}",
        identity[0], identity[1], identity[2]
    )
    .expect("writing to String");
    writeln!(manifest, "flash-size: {:#x}", flash_a.len()).expect("writing to String");
    writeln!(manifest, "sbr-offset: {SBR_FLASH_OFFSET:#x}").expect("writing to String");
    writeln!(manifest, "sbr-size: {:#x}", current_sbr.bytes().len()).expect("writing to String");
    writeln!(
        manifest,
        "expert-fields-enabled: {}",
        if policy.allow_expert_soc_fields {
            "yes"
        } else {
            "no"
        }
    )
    .expect("writing to String");
    writeln!(
        manifest,
        "expert-entries-enabled: {}",
        if policy.allow_expert_entries {
            "yes"
        } else {
            "no"
        }
    )
    .expect("writing to String");
    writeln!(manifest).expect("writing to String");
    writeln!(manifest, "files:").expect("writing to String");
    for (name, bytes) in files {
        writeln!(
            manifest,
            "  {name}: sha256={} size={:#x}",
            sha256_hex(bytes),
            bytes.len()
        )
        .expect("writing to String");
    }
    writeln!(
        manifest,
        "  {ATLAS_CONFIG_PLAN_FILE}: canonical machine-readable manifest (not self-hashed)"
    )
    .expect("writing to String");
    writeln!(manifest).expect("writing to String");
    writeln!(manifest, "named-differences:").expect("writing to String");
    for difference in &report.named_differences {
        writeln!(
            manifest,
            "  {}: {} -> {}",
            difference.field, difference.before, difference.after
        )
        .expect("writing to String");
    }
    writeln!(manifest, "station-differences:").expect("writing to String");
    for difference in &report.station_differences {
        writeln!(
            manifest,
            "  station {}: {:?} -> {:?}",
            difference.station, difference.before_codes, difference.after_codes
        )
        .expect("writing to String");
    }
    writeln!(manifest, "psb-entry-differences:").expect("writing to String");
    for difference in &report.psb_entry_differences {
        writeln!(
            manifest,
            "  entry {} {:?} register={:#x} descriptor={:#010x}: {:#010x} -> {:#010x}",
            difference.index,
            difference.register_key,
            difference.register_offset,
            difference.descriptor,
            difference.before,
            difference.after
        )
        .expect("writing to String");
    }
    writeln!(manifest, "psb-serdes-entry-differences:").expect("writing to String");
    for difference in &report.psb_serdes_entry_differences {
        writeln!(
            manifest,
            "  entry {} address={:#010x}: {:#010x} -> {:#010x}",
            difference.index, difference.address, difference.before, difference.after
        )
        .expect("writing to String");
    }
    writeln!(manifest).expect("writing to String");
    writeln!(manifest, "sbr-byte-differences:").expect("writing to String");
    for difference in &sbr_differences {
        writeln!(
            manifest,
            "  sbr={:#x} flash={:#x} {:02x}->{:02x}",
            difference.offset,
            sbr_offset + difference.offset,
            difference.before,
            difference.after
        )
        .expect("writing to String");
    }
    writeln!(manifest).expect("writing to String");
    let mut expert_options = String::new();
    if policy.allow_expert_soc_fields {
        expert_options.push_str(" --allow-expert-fields");
    }
    if policy.allow_expert_entries {
        expert_options.push_str(" --allow-expert-entries");
    }
    writeln!(
        manifest,
        "program-command: pexctl device program-plan --bdf {} --plan-dir .{expert_options} --confirm {required_confirmation}",
        device.bdf(),
    )
    .expect("writing to String");
    writeln!(manifest, "required-confirmation: {required_confirmation}")
        .expect("writing to String");
    writeln!(manifest, "hardware-written: no").expect("writing to String");

    let mut artifacts: Vec<_> = files
        .iter()
        .map(|(name, bytes)| AtlasConfigPlanArtifact::from_bytes(name, bytes))
        .collect();
    artifacts.push(AtlasConfigPlanArtifact::from_bytes(
        "MANIFEST.txt",
        manifest.as_bytes(),
    ));
    let plan_manifest = AtlasConfigPlanManifest::new(
        device.bdf(),
        device.vendor(),
        device.device(),
        identity,
        flash_a.len(),
        current_sbr.bytes().len(),
        policy,
        artifacts,
    )?;
    let plan_json = plan_manifest.to_json_pretty()?;

    create_new_directory(output_dir)?;
    for (name, bytes) in files {
        write_new_file(&output_dir.join(name), bytes)?;
    }
    write_new_file(&output_dir.join("MANIFEST.txt"), manifest.as_bytes())?;
    write_new_file(&output_dir.join(ATLAS_CONFIG_PLAN_FILE), &plan_json)?;
    verify_config_plan_directory(output_dir)?;

    println!(
        "prepared verified configuration plan in {}: {} named field change(s), {} station change(s), {} PSB entry change(s), {} PSB-SerDes entry change(s), {} changed SBR byte(s)",
        output_dir.display(),
        report.named_differences.len(),
        report.station_differences.len(),
        report.psb_entry_differences.len(),
        report.psb_serdes_entry_differences.len(),
        sbr_differences.len()
    );
    println!(
        "two complete {}-byte flash reads matched; hardware was not written",
        flash_a.len()
    );
    println!("required write confirmation: {required_confirmation}");
    Ok(())
}

fn create_new_directory(path: &Path) -> Result<()> {
    match fs::create_dir(path) {
        Ok(()) => Ok(()),
        Err(source) if source.kind() == io::ErrorKind::AlreadyExists => {
            Err(Error::Safety(format!(
                "{} already exists; choose a new plan directory",
                path.display()
            )))
        }
        Err(source) => Err(Error::io(
            format!("creating directory {}", path.display()),
            source,
        )),
    }
}

fn print_inspection(image: &SbrImage) {
    println!("format:       Broadcom Atlas SBR");
    println!("signature:    {:#010x} (PEX88096)", image.signature());
    println!(
        "length:       {:#x} ({})",
        image.bytes().len(),
        image.bytes().len()
    );
    println!("soc-settings: {:#x}..{:#x}", pexctl::SOC_OFFSET, SOC_END);
    println!(
        "soc-known:    upstream-port={} max-link-speed={} (code={}) lane-enable-code={} (raw)",
        image.upstream_port(),
        image.max_link_speed(),
        image.max_link_speed_code(),
        image.lane_enable_code_raw()
    );
    println!(
        "checksum:     stored={:#010x} expected={:#04x} offset={:#x} {}",
        image.stored_checksum(),
        image.expected_checksum(),
        image.checksum_offset(),
        if image.checksum_valid() {
            "valid"
        } else {
            "INVALID"
        }
    );
    println!("blocks:");
    for block in image.blocks() {
        println!(
            "  {:<11} offset={:#06x} size={:#06x} state={}",
            block.kind.name(),
            block.offset,
            block.size,
            block.state()
        );
    }
    println!("stations:");
    for station in 0..6 {
        let codes = image.station_codes(station).expect("fixed station range");
        let layout = image
            .inferred_station_layout(station)
            .expect("fixed station range")
            .map(|layout| layout.to_string())
            .unwrap_or_else(|| "unclassified".into());
        println!("  {station}: codes={codes:?} layout={layout}");
    }
}

fn print_diff(before: &SbrImage, after: &SbrImage) {
    println!(
        "length: {:#x} -> {:#x}",
        before.bytes().len(),
        after.bytes().len()
    );
    for station in 0..6 {
        let left = before.station_codes(station).expect("fixed station range");
        let right = after.station_codes(station).expect("fixed station range");
        if left != right {
            println!("station {station}: {left:?} -> {right:?}");
        }
    }
    let report = before.diff(after);
    for difference in report.psb_entry_differences {
        println!(
            "PSB entry {} {:?} register={:#x}: {:#010x} -> {:#010x}",
            difference.index,
            difference.register_key,
            difference.register_offset,
            difference.before,
            difference.after
        );
    }
    for difference in report.psb_serdes_entry_differences {
        println!(
            "PSB-SerDes entry {} address={:#010x}: {:#010x} -> {:#010x}",
            difference.index, difference.address, difference.before, difference.after
        );
    }
    for difference in byte_differences(before.bytes(), after.bytes()) {
        let label = if difference.offset == before.checksum_offset()
            || difference.offset == after.checksum_offset()
        {
            " checksum"
        } else {
            ""
        };
        println!(
            "{:#06x}: {:02x} -> {:02x}{label}",
            difference.offset, difference.before, difference.after
        );
    }
}

fn print_named_fields(inspection: &pexctl::SocFieldInspection) {
    println!("field                                      offset bits   value policy");
    for field in &inspection.fields {
        let bits = if field.bit_low == field.bit_high {
            field.bit_low.to_string()
        } else {
            format!("{}:{}", field.bit_high, field.bit_low)
        };
        println!(
            "{:<42} {:#06x} {:>5} {:>7} {}",
            field.name, field.offset, bits, field.value, field.write_policy
        );
    }
}

fn print_entry_inspection(inspection: &pexctl::SbrEntryInspection) {
    if !inspection.psb_entries.is_empty() {
        println!(
            "PSB register writes ({} entries):",
            inspection.psb_entries.len()
        );
        println!(
            "  idx sbr-off  register value      mask bcast descriptor reserved   policy    name"
        );
        for entry in &inspection.psb_entries {
            let name = entry.register_name.unwrap_or("unknown");
            println!(
                "  {:>3} {:#06x} {:#08x} {:#010x} {:#03x}  {:<3}   {:#010x} {:#010x} {:<9} {name}",
                entry.index,
                entry.sbr_offset,
                entry.register_offset,
                entry.value,
                entry.byte_mask,
                if entry.broadcast { "yes" } else { "no" },
                entry.descriptor,
                entry.reserved_bits,
                entry.write_policy
            );
        }
    }
    if !inspection.psb_entries.is_empty() && !inspection.psb_serdes_entries.is_empty() {
        println!();
    }
    if !inspection.psb_serdes_entries.is_empty() {
        println!(
            "PSB-SerDes AXI writes ({} entries):",
            inspection.psb_serdes_entries.len()
        );
        println!("  idx sbr-off  address    value      broadcast");
        for entry in &inspection.psb_serdes_entries {
            let broadcast = entry
                .broadcast_mode
                .map(|mode| mode.to_string())
                .unwrap_or_else(|| "n/a".into());
            println!(
                "  {:>3} {:#06x} {:#010x} {:#010x} {broadcast}",
                entry.index, entry.sbr_offset, entry.address, entry.value
            );
        }
    }
}

fn print_psw_inspection(inspection: &pexctl::PswInspection) {
    for (index, block) in inspection.blocks.iter().enumerate() {
        if index != 0 {
            println!();
        }
        println!(
            "{} station {}: state={} offset={:#x} size={:#x} expected-size={:#x} policy={}",
            block.block,
            block.station,
            block.state,
            block.offset,
            block.size,
            block.expected_size,
            block.write_policy
        );
        if block.lanes.is_empty() {
            println!("  no lane settings: block is not enabled");
            continue;
        }
        println!("  lane sbr-off raw  ssc protocol soft-control reserved");
        for lane in &block.lanes {
            println!(
                "  {:>4} {:#06x}  {:#04x} {:>3} {:>8} {:>12} {:#04x}",
                lane.lane,
                lane.sbr_offset,
                lane.raw_value,
                lane.ssc_default,
                lane.protocol_default,
                if lane.soft_control { "yes" } else { "no" },
                lane.reserved_bits
            );
        }
        if block.block == "pswx2" {
            println!(
                "  trailing reserved bits 31:16: {:#06x}",
                block.trailing_reserved_bits
            );
        }
    }
}

fn print_port_defaults_inspection(inspection: &pexctl::PortDefaultsInspection) {
    println!("port type type-off bits clock clock-off bits policy");
    for port in &inspection.ports {
        println!(
            "{:>4} {:>4}   {:#06x} {:>5}:{:<2} {:>5}    {:#06x} {:>5}:{:<2} {}",
            port.port,
            port.port_type_raw,
            port.port_type_offset,
            port.port_type_bit_high,
            port.port_type_bit_low,
            port.clock_mode_raw,
            port.clock_mode_offset,
            port.clock_mode_bit_high,
            port.clock_mode_bit_low,
            port.write_policy
        );
    }
}

fn option_value<'a>(args: &'a [String], name: &str) -> Result<&'a str> {
    let position = args
        .iter()
        .position(|argument| argument == name)
        .ok_or_else(|| Error::Usage(format!("missing required option {name}")))?;
    args.get(position + 1)
        .map(String::as_str)
        .filter(|value| !value.starts_with("--"))
        .ok_or_else(|| Error::Usage(format!("missing value for {name}")))
}

fn optional_number(args: &[String], name: &str) -> Result<Option<u64>> {
    if !args.iter().any(|argument| argument == name) {
        return Ok(None);
    }
    Ok(Some(parse_number(option_value(args, name)?)?))
}

fn optional_u8(args: &[String], name: &str) -> Result<Option<u8>> {
    optional_number(args, name)?
        .map(|value| {
            u8::try_from(value)
                .map_err(|_| Error::Usage(format!("{name} must fit in an unsigned byte")))
        })
        .transpose()
}

fn parse_number(value: &str) -> Result<u64> {
    let (digits, radix) = value
        .strip_prefix("0x")
        .or_else(|| value.strip_prefix("0X"))
        .map(|digits| (digits, 16))
        .unwrap_or((value, 10));
    u64::from_str_radix(digits, radix)
        .map_err(|_| Error::Usage(format!("invalid number {value:?}")))
}

fn reject_unknown_options(args: &[String], known: &[&str]) -> Result<()> {
    reject_unknown_options_and_flags(args, known, &[])
}

fn reject_unknown_options_and_flags(
    args: &[String],
    value_options: &[&str],
    flag_options: &[&str],
) -> Result<()> {
    let positional = args
        .iter()
        .take_while(|argument| !argument.starts_with("--"))
        .count();
    let mut index = positional;
    while index < args.len() {
        let option = &args[index];
        if args[positional..index]
            .iter()
            .any(|previous| previous == option)
        {
            return Err(Error::Usage(format!("duplicate option {option:?}")));
        }
        if flag_options.contains(&option.as_str()) {
            index += 1;
            continue;
        }
        if !value_options.contains(&option.as_str()) {
            return Err(Error::Usage(format!("unknown option {option:?}")));
        }
        if index + 1 >= args.len() || args[index + 1].starts_with("--") {
            return Err(Error::Usage(format!("missing value for {option}")));
        }
        index += 2;
    }
    Ok(())
}

fn expect_len(args: &[String], length: usize, usage: &str) -> Result<()> {
    if args.len() != length {
        return Err(Error::Usage(format!("usage: {usage}")));
    }
    Ok(())
}

fn optional_json_flag(args: &[String], positional_length: usize, usage: &str) -> Result<bool> {
    match args.get(positional_length..) {
        Some([]) => Ok(false),
        Some([flag]) if flag == "--json" => Ok(true),
        _ => Err(Error::Usage(format!("usage: {usage}"))),
    }
}

fn print_json<T: Serialize>(value: &T) -> Result<()> {
    let json = serde_json::to_string_pretty(value)
        .map_err(|error| Error::Config(format!("serializing JSON: {error}")))?;
    println!("{json}");
    Ok(())
}

fn json_bytes<T: Serialize>(value: &T) -> Result<Vec<u8>> {
    let mut bytes = serde_json::to_vec_pretty(value)
        .map_err(|error| Error::Config(format!("serializing JSON: {error}")))?;
    bytes.push(b'\n');
    Ok(bytes)
}

fn print_help() {
    println!(
        "\
pexctl — open Broadcom/PLX PEX switch configuration tools

USAGE:
  pexctl sbr inspect IMAGE [--json]
  pexctl sbr validate IMAGE
  pexctl sbr fields IMAGE [--json]
  pexctl sbr entries IMAGE [--block psb|psb-serdes] [--json]
  pexctl sbr psw IMAGE [--block psw0|psw1|psw2|psw3|psw4|psw5|pswx2] [--json]
  pexctl sbr ports IMAGE [--port N] [--json]
  pexctl sbr export-field-patch IMAGE --field NAME --value VALUE \
    --output CONFIG.json
  pexctl sbr export-entry-patch IMAGE --block psb|psb-serdes --index N \
    --value VALUE --output CONFIG.json
  pexctl sbr diff BEFORE AFTER [--json]
  pexctl sbr export-config IMAGE --output CONFIG.json
  pexctl sbr apply-config INPUT CONFIG.json --output OUTPUT \
    [--allow-expert-fields] [--allow-expert-entries]
  pexctl sbr set-station INPUT --station N --layout x16|x4x4x4x4 --output OUTPUT
  pexctl sbr repair-checksum INPUT --output OUTPUT

  pexctl flash extract-sbr FLASH --output OUTPUT [--offset 0x400]
  pexctl flash replace-sbr FLASH SBR --output OUTPUT [--offset 0x400]

  pexctl plan verify DIRECTORY [--json]

  sudo pexctl device read-sbr --bdf 0000:c4:00.0 --output OUTPUT [--offset 0x400]
  sudo pexctl device inspect-sbr --bdf 0000:c4:00.0 [--offset 0x400] [--json]
  sudo pexctl device fields --bdf 0000:c4:00.0 [--offset 0x400] [--json]
  sudo pexctl device entries --bdf 0000:c4:00.0 [--offset 0x400] \
    [--block psb|psb-serdes] [--json]
  sudo pexctl device psw --bdf 0000:c4:00.0 [--offset 0x400] \
    [--block psw0|psw1|psw2|psw3|psw4|psw5|pswx2] [--json]
  sudo pexctl device ports --bdf 0000:c4:00.0 [--offset 0x400] \
    [--port N] [--json]
  sudo pexctl device read-flash --bdf 0000:c4:00.0 --offset 0 --size 0x40000 \
    [--method mapped|serial] --output OUTPUT
  sudo pexctl device spi-id --bdf 0000:c4:00.0
  sudo pexctl device backup-flash --bdf 0000:c4:00.0 --output OUTPUT
  sudo pexctl device prepare-station --bdf 0000:c4:00.0 \
    --station N --layout x16|x4x4x4x4 --output-dir DIRECTORY
  sudo pexctl device prepare-config --bdf 0000:c4:00.0 \
    --config CONFIG.json --output-dir DIRECTORY \
    [--allow-expert-fields] [--allow-expert-entries]
  sudo pexctl device program-plan --bdf 0000:c4:00.0 \
    --plan-dir DIRECTORY \
    [--allow-expert-fields] [--allow-expert-entries] \
    --confirm ERASE-PROGRAM-VERIFY:0000:c4:00.0:CS0:SECTOR0
  sudo pexctl device program-sector0 --bdf 0000:c4:00.0 \
    --expected-current BACKUP --candidate CANDIDATE \
    --confirm ERASE-PROGRAM-VERIFY:0000:c4:00.0:CS0:SECTOR0

All mutation commands create a new file and refuse to overwrite an existing
path. Device reads use the PlxSvc ioctl ABI. Hardware write support is
limited to a whole, preserved sector 0 and requires an exact live-backup match,
validated SBR-only changes, an explicit device-bound confirmation, and complete
read-back verification. program-plan additionally verifies every prepared
artifact and reconstructs the candidate from its configuration before opening
the device. Expert fields additionally require expected-current values and
--allow-expert-fields. Expert indexed records require exact identity and
expected-current values plus --allow-expert-entries. No hardware command resets
the switch."
    );
}
