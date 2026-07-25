use pexctl::{
    byte_differences, sha256_hex, validate_sector0_replacement, write_new_file, Error,
    PlxSvcDevice, Result, SbrImage, StationLayout, ATLAS_SPI_RECOVERY_REGION_SIZE,
    SBR_FLASH_OFFSET, SOC_END,
};
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
            expect_len(args, 2, "pexctl sbr inspect IMAGE")?;
            let image = SbrImage::read(Path::new(&args[1]))?;
            print_inspection(&image);
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
        "diff" => {
            expect_len(args, 3, "pexctl sbr diff BEFORE AFTER")?;
            let before = SbrImage::read(Path::new(&args[1]))?;
            let after = SbrImage::read(Path::new(&args[2]))?;
            print_diff(&before, &after);
            Ok(())
        }
        "set-station" => run_set_station(&args[1..]),
        "repair-checksum" => run_repair_checksum(&args[1..]),
        other => Err(Error::Usage(format!("unknown SBR command {other:?}"))),
    }
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
        "prepare-station" => run_prepare_station(&args[1..]),
        "program-sector0" => {
            let options = &args[1..];
            let bdf = option_value(options, "--bdf")?;
            let expected_path = PathBuf::from(option_value(options, "--expected-current")?);
            let candidate_path = PathBuf::from(option_value(options, "--candidate")?);
            let confirmation = option_value(options, "--confirm")?;
            reject_unknown_options(
                options,
                &["--bdf", "--expected-current", "--candidate", "--confirm"],
            )?;
            let expected = fs::read(&expected_path).map_err(|source| {
                Error::io(format!("reading {}", expected_path.display()), source)
            })?;
            let candidate = fs::read(&candidate_path).map_err(|source| {
                Error::io(format!("reading {}", candidate_path.display()), source)
            })?;
            validate_sector0_replacement(&expected, &candidate)?;
            let device = PlxSvcDevice::open(bdf)?;
            let required_confirmation = format!(
                "ERASE-PROGRAM-VERIFY:{}:CS0:SECTOR0",
                device.bdf().to_ascii_lowercase()
            );
            if confirmation != required_confirmation {
                return Err(Error::Safety(format!(
                    "confirmation mismatch; this operation requires --confirm {required_confirmation:?}"
                )));
            }
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

fn run_prepare_station(options: &[String]) -> Result<()> {
    let bdf = option_value(options, "--bdf")?;
    let station = option_value(options, "--station")?
        .parse::<usize>()
        .map_err(|_| Error::Usage("--station must be an integer from 0 through 5".into()))?;
    let layout = StationLayout::parse(option_value(options, "--layout")?)?;
    let output_dir = PathBuf::from(option_value(options, "--output-dir")?);
    reject_unknown_options(options, &["--bdf", "--station", "--layout", "--output-dir"])?;
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
    let old_codes = current_sbr.station_codes(station)?;

    let mut candidate_sbr = current_sbr.clone();
    candidate_sbr.set_station_layout(station, layout)?;
    candidate_sbr.validate()?;
    let new_codes = candidate_sbr.station_codes(station)?;
    let sbr_differences = byte_differences(current_sbr.bytes(), candidate_sbr.bytes());
    if sbr_differences.is_empty() {
        return Err(Error::Safety(format!(
            "station {station} already has layout {layout}; no plan directory was created"
        )));
    }

    let current_region = flash_a[..ATLAS_SPI_RECOVERY_REGION_SIZE].to_vec();
    let mut candidate_region = current_region.clone();
    let sbr_end = sbr_offset
        .checked_add(candidate_sbr.bytes().len())
        .ok_or_else(|| Error::Usage("candidate SBR range overflow".into()))?;
    candidate_region[sbr_offset..sbr_end].copy_from_slice(candidate_sbr.bytes());
    validate_sector0_replacement(&current_region, &candidate_region)?;

    let required_confirmation = format!(
        "ERASE-PROGRAM-VERIFY:{}:CS0:SECTOR0",
        device.bdf().to_ascii_lowercase()
    );
    let files = [
        ("current-flash-a.bin", flash_a.as_slice()),
        ("current-flash-b.bin", flash_b.as_slice()),
        ("current-region.bin", current_region.as_slice()),
        ("current-sbr.bin", current_sbr.bytes()),
        ("candidate-region.bin", candidate_region.as_slice()),
        ("candidate-sbr.bin", candidate_sbr.bytes()),
    ];

    let mut manifest = String::new();
    writeln!(manifest, "format: pexctl-station-plan-v1").expect("writing to String");
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
    writeln!(manifest, "station: {station}").expect("writing to String");
    writeln!(manifest, "old-codes: {old_codes:?}").expect("writing to String");
    writeln!(manifest, "new-codes: {new_codes:?}").expect("writing to String");
    writeln!(manifest, "new-layout: {layout}").expect("writing to String");
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
    writeln!(
        manifest,
        "program-command: pexctl device program-sector0 --bdf {} --expected-current current-region.bin --candidate candidate-region.bin --confirm {required_confirmation}",
        device.bdf()
    )
    .expect("writing to String");
    writeln!(manifest, "required-confirmation: {required_confirmation}")
        .expect("writing to String");
    writeln!(manifest, "hardware-written: no").expect("writing to String");

    create_new_directory(&output_dir)?;
    for (name, bytes) in files {
        write_new_file(&output_dir.join(name), bytes)?;
    }
    write_new_file(&output_dir.join("MANIFEST.txt"), manifest.as_bytes())?;

    println!(
        "prepared verified station plan in {}: station {} {:?} -> {:?} ({layout})",
        output_dir.display(),
        station,
        old_codes,
        new_codes
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

fn parse_number(value: &str) -> Result<u64> {
    let (digits, radix) = value
        .strip_prefix("0x")
        .map(|digits| (digits, 16))
        .unwrap_or((value, 10));
    u64::from_str_radix(digits, radix)
        .map_err(|_| Error::Usage(format!("invalid number {value:?}")))
}

fn reject_unknown_options(args: &[String], known: &[&str]) -> Result<()> {
    let positional = args
        .iter()
        .take_while(|argument| !argument.starts_with("--"))
        .count();
    let mut index = positional;
    while index < args.len() {
        let option = &args[index];
        if !known.contains(&option.as_str()) {
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

fn print_help() {
    println!(
        "\
pexctl — open Broadcom/PLX PEX switch configuration tools

USAGE:
  pexctl sbr inspect IMAGE
  pexctl sbr validate IMAGE
  pexctl sbr diff BEFORE AFTER
  pexctl sbr set-station INPUT --station N --layout x16|x4x4x4x4 --output OUTPUT
  pexctl sbr repair-checksum INPUT --output OUTPUT

  pexctl flash extract-sbr FLASH --output OUTPUT [--offset 0x400]
  pexctl flash replace-sbr FLASH SBR --output OUTPUT [--offset 0x400]

  sudo pexctl device read-sbr --bdf 0000:c4:00.0 --output OUTPUT [--offset 0x400]
  sudo pexctl device read-flash --bdf 0000:c4:00.0 --offset 0 --size 0x40000 \
    [--method mapped|serial] --output OUTPUT
  sudo pexctl device spi-id --bdf 0000:c4:00.0
  sudo pexctl device backup-flash --bdf 0000:c4:00.0 --output OUTPUT
  sudo pexctl device prepare-station --bdf 0000:c4:00.0 \
    --station N --layout x16|x4x4x4x4 --output-dir DIRECTORY
  sudo pexctl device program-sector0 --bdf 0000:c4:00.0 \
    --expected-current BACKUP --candidate CANDIDATE \
    --confirm ERASE-PROGRAM-VERIFY:0000:c4:00.0:CS0:SECTOR0

All mutation commands create a new file and refuse to overwrite an existing
path. Device reads use the PlxSvc ioctl ABI. Hardware write support is
limited to a whole, preserved sector 0 and requires an exact live-backup match,
validated SBR-only changes, an explicit device-bound confirmation, and complete
read-back verification. No hardware command resets the switch."
    );
}
