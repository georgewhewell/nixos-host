//! Lossless helpers for Broadcom/PLX Atlas SBR images and live devices.
//!
//! The format support here is deliberately conservative. Unknown bytes are
//! retained verbatim, and mutation APIs expose only fields that have been
//! confirmed against both a live PEX88096 image and Broadcom's RDK96 image.

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fmt;
use std::fs;
use std::io::{self, Write};
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

pub const ATLAS_SIGNATURE_PEX88096: u32 = 0xc010_3dc4;
pub const SBR_FLASH_OFFSET: u64 = 0x400;
pub const ATLAS_SPI_CS0_MAPPED_OFFSET: u64 = 0x30_0000;
pub const ATLAS_PORT_REGISTERS_MAPPED_OFFSET: u64 = 0x80_0000;
pub const ATLAS_SPI_RECOVERY_REGION_SIZE: usize = 1 << 18;
pub const ATLAS_SPI_ERASE_BLOCK_SIZE: usize = 1 << 16;
pub const SBR_SIGNATURE_SIZE: usize = 4;
pub const SBR_INDEX_OFFSET: usize = 4;
pub const SBR_INDEX_DWORDS: usize = 22;
pub const SBR_INDEX_SIZE: usize = SBR_INDEX_DWORDS * 4;
pub const SOC_OFFSET: usize = SBR_INDEX_OFFSET + SBR_INDEX_SIZE;
pub const SOC_SIZE: usize = 0x1a0;
pub const SOC_END: usize = SOC_OFFSET + SOC_SIZE;
pub const CHECKSUM_SEED: u8 = 0xa5;
pub const MAX_SBR_SIZE: usize = 128 * 1024;
pub const ATLAS_CONFIG_SCHEMA: &str = "pexctl.atlas-config.v1";
pub const ATLAS_CONFIG_PLAN_SCHEMA: &str = "pexctl.atlas-config-plan.v1";
pub const ATLAS_INSPECTION_SCHEMA: &str = "pexctl.atlas-sbr-inspection.v1";
pub const ATLAS_DIFF_SCHEMA: &str = "pexctl.atlas-sbr-diff.v1";
pub const ATLAS_ENTRY_INSPECTION_SCHEMA: &str = "pexctl.atlas-entry-inspection.v1";
pub const ATLAS_PSW_INSPECTION_SCHEMA: &str = "pexctl.atlas-psw-inspection.v1";
pub const ATLAS_SOC_FIELD_INSPECTION_SCHEMA: &str = "pexctl.atlas-soc-field-inspection.v1";
pub const ATLAS_PORT_DEFAULT_INSPECTION_SCHEMA: &str = "pexctl.atlas-port-default-inspection.v1";
pub const SPI_FLASH_STATUS_SCHEMA: &str = "pexctl.spi-flash-status.v1";
pub const ATLAS_CONFIG_PLAN_FILE: &str = "PLAN.json";
pub const ATLAS_CONFIG_PLAN_ARTIFACT_NAMES: [&str; 11] = [
    "current-flash-a.bin",
    "current-flash-b.bin",
    "current-region.bin",
    "current-sbr.bin",
    "candidate-region.bin",
    "candidate-sbr.bin",
    "applied-config.json",
    "current-inspection.json",
    "candidate-inspection.json",
    "diff.json",
    "MANIFEST.txt",
];
const PSB_MAX_SIZE: u32 = 0x2000;
const PSB_SERDES_MAX_SIZE: u32 = 0x4000;
const MAX_CONFIG_PLAN_JSON_SIZE: u64 = 4 * 1024 * 1024;
const PSB_REGISTER_WORD_MASK: u32 = 0x000f_ffff;
const PSB_BYTE_MASK_MASK: u32 = 0x0f00_0000;
const PSB_BROADCAST_MASK: u32 = 0x1000_0000;
const AXI_BROADCAST_ADDRESS_MASK: u32 = 0x7000_0000;
const AXI_BROADCAST_ADDRESS_VALUE: u32 = 0x7000_0000;
const AXI_BROADCAST_MODE_MASK: u32 = 0x0300_0000;
// The v1 plan stores complete inspection JSON byte-for-byte. Keep this prefix
// ordered and immutable; append newly understood fields after it.
const ATLAS_INSPECTION_V1_SOC_FIELD_COUNT: usize = 35;
const UPSTREAM_PORT_START_BIT: usize = SOC_OFFSET * 8;
const MAX_LINK_SPEED_START_BIT: usize = SOC_OFFSET * 8 + 8;
const LANE_ENABLE_START_BIT: usize = SOC_OFFSET * 8 + 13;
const STATION_CONFIG_START_BIT: usize = SOC_OFFSET * 8 + 16;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug)]
pub enum Error {
    Io { context: String, source: io::Error },
    Device(String),
    Format(String),
    Config(String),
    Usage(String),
    Safety(String),
}

impl Error {
    pub fn io(context: impl Into<String>, source: io::Error) -> Self {
        Self::Io {
            context: context.into(),
            source,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io { context, source } => write!(f, "{context}: {source}"),
            Self::Device(message) => write!(f, "device error: {message}"),
            Self::Format(message) => write!(f, "invalid SBR: {message}"),
            Self::Config(message) => write!(f, "invalid configuration: {message}"),
            Self::Usage(message) => write!(f, "{message}"),
            Self::Safety(message) => write!(f, "refusing unsafe operation: {message}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BlockKind {
    Psb,
    Psw0,
    Psw1,
    Psw2,
    Psw3,
    Psw4,
    Psw5,
    Pswx2,
    PsbSerdes,
}

impl BlockKind {
    pub const ALL: [Self; 9] = [
        Self::Psb,
        Self::Psw0,
        Self::Psw1,
        Self::Psw2,
        Self::Psw3,
        Self::Psw4,
        Self::Psw5,
        Self::Pswx2,
        Self::PsbSerdes,
    ];
    pub const PSW: [Self; 7] = [
        Self::Psw0,
        Self::Psw1,
        Self::Psw2,
        Self::Psw3,
        Self::Psw4,
        Self::Psw5,
        Self::Pswx2,
    ];

    fn index_pair(self) -> (usize, usize) {
        match self {
            Self::Psb => (0, 1),
            Self::Psw0 => (2, 3),
            Self::Psw1 => (4, 5),
            Self::Psw2 => (6, 7),
            Self::Psw3 => (8, 9),
            Self::Psw4 => (10, 11),
            Self::Psw5 => (12, 13),
            // Atlas reserves an offset/size pair at index entries 14 and 15.
            Self::Pswx2 => (16, 17),
            Self::PsbSerdes => (18, 19),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Psb => "psb",
            Self::Psw0 => "psw0",
            Self::Psw1 => "psw1",
            Self::Psw2 => "psw2",
            Self::Psw3 => "psw3",
            Self::Psw4 => "psw4",
            Self::Psw5 => "psw5",
            Self::Pswx2 => "pswx2",
            Self::PsbSerdes => "psb-serdes",
        }
    }

    fn max_size(self) -> Option<u32> {
        match self {
            Self::Psb => Some(PSB_MAX_SIZE),
            Self::PsbSerdes => Some(PSB_SERDES_MAX_SIZE),
            _ => None,
        }
    }

    fn exact_size(self) -> Option<u32> {
        match self {
            Self::Psw0 | Self::Psw1 | Self::Psw2 | Self::Psw3 | Self::Psw4 | Self::Psw5 => Some(16),
            Self::Pswx2 => Some(4),
            _ => None,
        }
    }

    fn psw_station(self) -> Option<&'static str> {
        match self {
            Self::Psw0 => Some("0"),
            Self::Psw1 => Some("1"),
            Self::Psw2 => Some("2"),
            Self::Psw3 => Some("3"),
            Self::Psw4 => Some("4"),
            Self::Psw5 => Some("5"),
            Self::Pswx2 => Some("x2"),
            _ => None,
        }
    }

    fn requires_entry_pairs(self) -> bool {
        matches!(self, Self::Psb | Self::PsbSerdes)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BlockState {
    Enabled,
    Ignored,
    End,
    Invalid,
}

impl fmt::Display for BlockState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Enabled => f.write_str("enabled"),
            Self::Ignored => f.write_str("ignored"),
            Self::End => f.write_str("end"),
            Self::Invalid => f.write_str("invalid"),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Block {
    pub kind: BlockKind,
    pub offset: u32,
    pub size: u32,
}

impl Block {
    pub fn state(self) -> BlockState {
        match (self.offset, self.size) {
            (0, 0) => BlockState::End,
            (0, _) => BlockState::Ignored,
            (_, 0) => BlockState::Invalid,
            (_, _) => BlockState::Enabled,
        }
    }

    pub fn end(self) -> Option<u32> {
        (self.state() == BlockState::Enabled).then(|| self.offset.saturating_add(self.size))
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum StationLayout {
    #[serde(rename = "x16")]
    X16,
    #[serde(rename = "x4x4x4x4", alias = "x4+x4+x4+x4")]
    X4X4X4X4,
}

impl StationLayout {
    pub fn parse(value: &str) -> Result<Self> {
        match value
            .to_ascii_lowercase()
            .replace(['+', '-', '_'], "")
            .as_str()
        {
            "x16" | "16" => Ok(Self::X16),
            "x4x4x4x4" | "4x4x4x4" | "4444" => Ok(Self::X4X4X4X4),
            _ => Err(Error::Usage(format!(
                "unsupported layout {value:?}; confirmed layouts are x16 and x4x4x4x4"
            ))),
        }
    }

    pub fn codes(self) -> [u8; 4] {
        match self {
            Self::X16 => [0, 0, 0, 0],
            Self::X4X4X4X4 => [1, 1, 1, 1],
        }
    }
}

impl fmt::Display for StationLayout {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::X16 => f.write_str("x16"),
            Self::X4X4X4X4 => f.write_str("x4+x4+x4+x4"),
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum PcieGeneration {
    #[serde(rename = "gen1")]
    Gen1,
    #[serde(rename = "gen2")]
    Gen2,
    #[serde(rename = "gen3")]
    Gen3,
    #[serde(rename = "gen4")]
    Gen4,
}

impl PcieGeneration {
    pub fn from_code(code: u8) -> Self {
        match code {
            0 => Self::Gen1,
            1 => Self::Gen2,
            2 => Self::Gen3,
            3 => Self::Gen4,
            _ => unreachable!("two-bit PCIe generation code"),
        }
    }

    pub fn code(self) -> u8 {
        match self {
            Self::Gen1 => 0,
            Self::Gen2 => 1,
            Self::Gen3 => 2,
            Self::Gen4 => 3,
        }
    }
}

impl fmt::Display for PcieGeneration {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Gen1 => f.write_str("gen1"),
            Self::Gen2 => f.write_str("gen2"),
            Self::Gen3 => f.write_str("gen3"),
            Self::Gen4 => f.write_str("gen4"),
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AtlasSocConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub upstream_port: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_link_speed: Option<PcieGeneration>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AtlasStationConfig {
    pub station: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub layout: Option<StationLayout>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExpertSocFieldPatch {
    pub field: String,
    pub expected: u8,
    pub value: u8,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExpertPsbEntryPatch {
    pub index: usize,
    pub register_key: String,
    #[serde(
        deserialize_with = "deserialize_u32",
        serialize_with = "serialize_u32_hex"
    )]
    pub expected_descriptor: u32,
    #[serde(
        deserialize_with = "deserialize_u32",
        serialize_with = "serialize_u32_hex"
    )]
    pub expected_value: u32,
    #[serde(
        deserialize_with = "deserialize_u32",
        serialize_with = "serialize_u32_hex"
    )]
    pub value: u32,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExpertPsbSerdesEntryPatch {
    pub index: usize,
    #[serde(
        deserialize_with = "deserialize_u32",
        serialize_with = "serialize_u32_hex"
    )]
    pub expected_address: u32,
    #[serde(
        deserialize_with = "deserialize_u32",
        serialize_with = "serialize_u32_hex"
    )]
    pub expected_value: u32,
    #[serde(
        deserialize_with = "deserialize_u32",
        serialize_with = "serialize_u32_hex"
    )]
    pub value: u32,
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AtlasConfig {
    pub schema: String,
    #[serde(default, skip_serializing_if = "AtlasSocConfig::is_empty")]
    pub soc: AtlasSocConfig,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub stations: Vec<AtlasStationConfig>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub expert_soc_fields: Vec<ExpertSocFieldPatch>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub expert_psb_entries: Vec<ExpertPsbEntryPatch>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub expert_psb_serdes_entries: Vec<ExpertPsbSerdesEntryPatch>,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AtlasApplyPolicy {
    pub allow_expert_soc_fields: bool,
    pub allow_expert_entries: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AtlasConfigPlanArtifact {
    pub name: String,
    pub size: usize,
    pub sha256: String,
}

impl AtlasConfigPlanArtifact {
    pub fn from_bytes(name: &str, bytes: &[u8]) -> Self {
        Self {
            name: name.into(),
            size: bytes.len(),
            sha256: sha256_hex(bytes),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AtlasConfigPlanManifest {
    pub schema: String,
    pub bdf: String,
    pub pci_vendor: u16,
    pub pci_device: u16,
    pub jedec_id: [u8; 3],
    pub flash_size: usize,
    pub sbr_offset: u64,
    pub sbr_size: usize,
    pub policy: AtlasApplyPolicy,
    pub artifacts: Vec<AtlasConfigPlanArtifact>,
    pub required_confirmation: String,
    pub hardware_written: bool,
}

impl AtlasConfigPlanManifest {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        bdf: &str,
        pci_vendor: u16,
        pci_device: u16,
        jedec_id: [u8; 3],
        flash_size: usize,
        sbr_size: usize,
        policy: AtlasApplyPolicy,
        artifacts: Vec<AtlasConfigPlanArtifact>,
    ) -> Result<Self> {
        let bdf = normalize_bdf(bdf)?;
        let manifest = Self {
            schema: ATLAS_CONFIG_PLAN_SCHEMA.into(),
            required_confirmation: required_confirmation(&bdf)?,
            bdf,
            pci_vendor,
            pci_device,
            jedec_id,
            flash_size,
            sbr_offset: SBR_FLASH_OFFSET,
            sbr_size,
            policy,
            artifacts,
            hardware_written: false,
        };
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn parse_json(bytes: &[u8]) -> Result<Self> {
        let manifest: Self = serde_json::from_slice(bytes)
            .map_err(|error| Error::Config(format!("plan JSON: {error}")))?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn to_json_pretty(&self) -> Result<Vec<u8>> {
        self.validate()?;
        json_pretty_bytes(self)
    }

    pub fn validate(&self) -> Result<()> {
        if self.schema != ATLAS_CONFIG_PLAN_SCHEMA {
            return Err(Error::Config(format!(
                "unsupported plan schema {:?}; expected {ATLAS_CONFIG_PLAN_SCHEMA:?}",
                self.schema
            )));
        }
        let normalized_bdf = normalize_bdf(&self.bdf)?;
        if self.bdf != normalized_bdf {
            return Err(Error::Config(format!(
                "plan BDF {:?} is not normalized as {normalized_bdf:?}",
                self.bdf
            )));
        }
        if self.pci_vendor != 0x1000 || self.pci_device != 0xc010 {
            return Err(Error::Config(format!(
                "unsupported plan PCI identity {:04x}:{:04x}; writable plans are proven only for PEX88096 1000:c010",
                self.pci_vendor, self.pci_device
            )));
        }
        let expected_flash_size = supported_flash_capacity(self.jedec_id)?;
        if self.flash_size != expected_flash_size {
            return Err(Error::Config(format!(
                "plan flash_size {:#x} disagrees with JEDEC ID {:02x?} capacity {expected_flash_size:#x}",
                self.flash_size, self.jedec_id
            )));
        }
        if self.sbr_offset != SBR_FLASH_OFFSET {
            return Err(Error::Config(format!(
                "plan SBR offset {:#x} differs from supported Atlas offset {SBR_FLASH_OFFSET:#x}",
                self.sbr_offset
            )));
        }
        if !(SOC_END + 4..=MAX_SBR_SIZE).contains(&self.sbr_size) {
            return Err(Error::Config(format!(
                "plan SBR size {:#x} is outside the supported range",
                self.sbr_size
            )));
        }
        if self.required_confirmation != required_confirmation(&self.bdf)? {
            return Err(Error::Config(
                "plan required_confirmation is not bound to its BDF".into(),
            ));
        }
        if self.hardware_written {
            return Err(Error::Safety(
                "plan claims hardware_written=true and cannot be reused".into(),
            ));
        }
        if self.artifacts.len() != ATLAS_CONFIG_PLAN_ARTIFACT_NAMES.len() {
            return Err(Error::Config(format!(
                "plan must contain exactly {} artifact records",
                ATLAS_CONFIG_PLAN_ARTIFACT_NAMES.len()
            )));
        }
        for (artifact, expected_name) in self.artifacts.iter().zip(ATLAS_CONFIG_PLAN_ARTIFACT_NAMES)
        {
            if artifact.name != expected_name {
                return Err(Error::Config(format!(
                    "plan artifact {:?} is out of order or unexpected; expected {expected_name:?}",
                    artifact.name
                )));
            }
            if artifact.sha256.len() != 64
                || !artifact
                    .sha256
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
            {
                return Err(Error::Config(format!(
                    "plan artifact {:?} has a non-canonical SHA-256",
                    artifact.name
                )));
            }
            let expected_size = match artifact.name.as_str() {
                "current-flash-a.bin" | "current-flash-b.bin" => Some(self.flash_size),
                "current-region.bin" | "candidate-region.bin" => {
                    Some(ATLAS_SPI_RECOVERY_REGION_SIZE)
                }
                "current-sbr.bin" | "candidate-sbr.bin" => Some(self.sbr_size),
                _ => None,
            };
            if let Some(expected_size) = expected_size {
                if artifact.size != expected_size {
                    return Err(Error::Config(format!(
                        "plan artifact {:?} size {:#x} differs from required size {expected_size:#x}",
                        artifact.name, artifact.size
                    )));
                }
            } else if artifact.size == 0 || artifact.size as u64 > MAX_CONFIG_PLAN_JSON_SIZE {
                return Err(Error::Config(format!(
                    "plan metadata artifact {:?} has unsupported size {:#x}",
                    artifact.name, artifact.size
                )));
            }
        }
        Ok(())
    }
}

#[derive(Debug)]
pub struct VerifiedAtlasConfigPlan {
    manifest: AtlasConfigPlanManifest,
    expected_current: Vec<u8>,
    candidate: Vec<u8>,
}

impl VerifiedAtlasConfigPlan {
    pub fn manifest(&self) -> &AtlasConfigPlanManifest {
        &self.manifest
    }

    pub fn expected_current(&self) -> &[u8] {
        &self.expected_current
    }

    pub fn candidate(&self) -> &[u8] {
        &self.candidate
    }
}

impl AtlasSocConfig {
    pub fn is_empty(&self) -> bool {
        self.upstream_port.is_none() && self.max_link_speed.is_none()
    }
}

impl AtlasConfig {
    pub fn station_layout(station: u8, layout: StationLayout) -> Result<Self> {
        let config = Self {
            schema: ATLAS_CONFIG_SCHEMA.into(),
            soc: AtlasSocConfig::default(),
            stations: vec![AtlasStationConfig {
                station,
                layout: Some(layout),
            }],
            expert_soc_fields: Vec::new(),
            expert_psb_entries: Vec::new(),
            expert_psb_serdes_entries: Vec::new(),
        };
        config.validate()?;
        Ok(config)
    }

    pub fn parse_json(bytes: &[u8]) -> Result<Self> {
        let config: Self = serde_json::from_slice(bytes)
            .map_err(|error| Error::Config(format!("JSON: {error}")))?;
        config.validate()?;
        Ok(config)
    }

    pub fn read(path: &Path) -> Result<Self> {
        let bytes = fs::read(path)
            .map_err(|source| Error::io(format!("reading {}", path.display()), source))?;
        Self::parse_json(&bytes)
    }

    pub fn to_json_pretty(&self) -> Result<Vec<u8>> {
        self.validate()?;
        let mut bytes = serde_json::to_vec_pretty(self)
            .map_err(|error| Error::Config(format!("serializing JSON: {error}")))?;
        bytes.push(b'\n');
        Ok(bytes)
    }

    pub fn validate(&self) -> Result<()> {
        if self.schema != ATLAS_CONFIG_SCHEMA {
            return Err(Error::Config(format!(
                "unsupported schema {:?}; expected {ATLAS_CONFIG_SCHEMA:?}",
                self.schema
            )));
        }
        if let Some(upstream_port) = self.soc.upstream_port {
            if port_default_location(upstream_port).is_none() {
                return Err(Error::Config(format!(
                    "upstream port {upstream_port} is not a database-defined PEX88096 port (0-95, 116, or 117)"
                )));
            }
        }
        let mut seen = [false; 6];
        for entry in &self.stations {
            let station = usize::from(entry.station);
            if station >= seen.len() {
                return Err(Error::Config(format!(
                    "station must be 0 through 5, got {}",
                    entry.station
                )));
            }
            if seen[station] {
                return Err(Error::Config(format!(
                    "station {} appears more than once",
                    entry.station
                )));
            }
            seen[station] = true;
        }
        let mut seen_expert_fields: Vec<&str> = Vec::new();
        for patch in &self.expert_soc_fields {
            let field = named_soc_field(&patch.field).ok_or_else(|| {
                Error::Config(format!(
                    "unknown expert SoC field {:?}; use `pexctl sbr fields IMAGE` to list named fields",
                    patch.field
                ))
            })?;
            if field.writable {
                return Err(Error::Config(format!(
                    "{:?} has an ordinary typed configuration field; do not configure it through expert_soc_fields",
                    patch.field
                )));
            }
            if seen_expert_fields.contains(&patch.field.as_str()) {
                return Err(Error::Config(format!(
                    "expert SoC field {:?} appears more than once",
                    patch.field
                )));
            }
            seen_expert_fields.push(&patch.field);
            let maximum = ((1u16 << field.width) - 1) as u8;
            if patch.expected > maximum || patch.value > maximum {
                return Err(Error::Config(format!(
                    "{:?} is {} bit(s) wide, so expected and value must be at most {maximum}",
                    patch.field, field.width
                )));
            }
        }
        let mut seen_psb_entries = Vec::new();
        for patch in &self.expert_psb_entries {
            if seen_psb_entries.contains(&patch.index) {
                return Err(Error::Config(format!(
                    "expert PSB entry {} appears more than once",
                    patch.index
                )));
            }
            seen_psb_entries.push(patch.index);
            let register = known_psb_register_by_key(&patch.register_key).ok_or_else(|| {
                Error::Config(format!(
                    "unknown PSB register key {:?}; use `pexctl sbr entries IMAGE --block psb` to list known keys",
                    patch.register_key
                ))
            })?;
            if !register.expert_writable {
                return Err(Error::Config(format!(
                    "PSB register key {:?} is classified as reserved and is not writable",
                    patch.register_key
                )));
            }
            let descriptor_offset = (patch.expected_descriptor & PSB_REGISTER_WORD_MASK) << 2;
            if descriptor_offset != register.offset {
                return Err(Error::Config(format!(
                    "expert PSB entry {} key {:?} resolves to register {:#x}, but expected_descriptor resolves to {descriptor_offset:#x}",
                    patch.index, patch.register_key, register.offset
                )));
            }
            if patch.expected_value == patch.value {
                return Err(Error::Config(format!(
                    "expert PSB entry {} expected_value and value are identical",
                    patch.index
                )));
            }
            let byte_mask = ((patch.expected_descriptor & PSB_BYTE_MASK_MASK) >> 24) as u8;
            let writable_mask = psb_value_mask(byte_mask);
            let changed_bits = patch.expected_value ^ patch.value;
            if changed_bits & !writable_mask != 0 {
                return Err(Error::Config(format!(
                    "expert PSB entry {} changes bits outside descriptor byte mask {byte_mask:#x}",
                    patch.index
                )));
            }
        }
        let mut seen_psb_serdes_entries = Vec::new();
        for patch in &self.expert_psb_serdes_entries {
            if seen_psb_serdes_entries.contains(&patch.index) {
                return Err(Error::Config(format!(
                    "expert PSB-SerDes entry {} appears more than once",
                    patch.index
                )));
            }
            seen_psb_serdes_entries.push(patch.index);
            if patch.expected_value == patch.value {
                return Err(Error::Config(format!(
                    "expert PSB-SerDes entry {} expected_value and value are identical",
                    patch.index
                )));
            }
        }
        if self.soc.is_empty()
            && self.stations.iter().all(|entry| entry.layout.is_none())
            && self.expert_soc_fields.is_empty()
            && self.expert_psb_entries.is_empty()
            && self.expert_psb_serdes_entries.is_empty()
        {
            return Err(Error::Config(
                "configuration contains no writable values".into(),
            ));
        }
        Ok(())
    }

    pub fn validate_with_policy(&self, policy: AtlasApplyPolicy) -> Result<()> {
        self.validate()?;
        if !self.expert_soc_fields.is_empty() && !policy.allow_expert_soc_fields {
            return Err(Error::Safety(
                "configuration contains expert_soc_fields; pass --allow-expert-fields to acknowledge that their board behavior is not independently validated"
                    .into(),
            ));
        }
        if (!self.expert_psb_entries.is_empty() || !self.expert_psb_serdes_entries.is_empty())
            && !policy.allow_expert_entries
        {
            return Err(Error::Safety(
                "configuration contains expert PSB/PSB-SerDes entries; pass --allow-expert-entries to acknowledge that their register behavior is not independently validated"
                    .into(),
            ));
        }
        Ok(())
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct ChecksumInspection {
    pub offset: usize,
    pub stored: u32,
    pub expected: u8,
    pub valid: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SocInspection {
    pub offset: usize,
    pub size: usize,
    pub sha256: String,
    pub raw_dwords: Vec<u32>,
    pub upstream_port: u8,
    pub max_link_speed: PcieGeneration,
    pub max_link_speed_code: u8,
    pub lane_enable_code_raw: u8,
    pub named_fields: Vec<NamedSocFieldInspection>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct NamedSocFieldInspection {
    pub name: &'static str,
    pub offset: usize,
    pub bit_low: u8,
    pub bit_high: u8,
    pub value: u8,
    pub writable: bool,
    pub write_policy: &'static str,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SocFieldInspection {
    pub schema: &'static str,
    pub sbr_sha256: String,
    pub fields: Vec<NamedSocFieldInspection>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PortDefaultInspection {
    pub port: u8,
    pub port_type_raw: u8,
    pub port_type_offset: usize,
    pub port_type_bit_low: u8,
    pub port_type_bit_high: u8,
    pub clock_mode_raw: u8,
    pub clock_mode_offset: usize,
    pub clock_mode_bit_low: u8,
    pub clock_mode_bit_high: u8,
    pub write_policy: &'static str,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PortDefaultsInspection {
    pub schema: &'static str,
    pub sbr_sha256: String,
    pub ports: Vec<PortDefaultInspection>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct BlockInspection {
    pub name: &'static str,
    pub offset: u32,
    pub size: u32,
    pub state: String,
    pub sha256: Option<String>,
    pub raw_dwords: Vec<u32>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum AxiBroadcastMode {
    None,
    Lane,
    Station,
    Both,
}

impl AxiBroadcastMode {
    fn from_code(code: u8) -> Self {
        match code {
            0 => Self::None,
            1 => Self::Lane,
            2 => Self::Station,
            3 => Self::Both,
            _ => unreachable!("two-bit AXI broadcast code"),
        }
    }
}

impl fmt::Display for AxiBroadcastMode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::None => f.write_str("none"),
            Self::Lane => f.write_str("lane"),
            Self::Station => f.write_str("station"),
            Self::Both => f.write_str("lane+station"),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PsbEntryInspection {
    pub index: usize,
    pub sbr_offset: usize,
    pub value: u32,
    pub descriptor: u32,
    pub register_offset: u32,
    pub register_key: Option<&'static str>,
    pub register_name: Option<&'static str>,
    pub expert_writable: bool,
    pub write_policy: &'static str,
    pub byte_mask: u8,
    pub broadcast: bool,
    pub reserved_bits: u32,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PsbSerdesEntryInspection {
    pub index: usize,
    pub sbr_offset: usize,
    pub address: u32,
    pub value: u32,
    pub broadcast_mode: Option<AxiBroadcastMode>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SbrEntryInspection {
    pub schema: &'static str,
    pub sbr_sha256: String,
    pub psb_entries: Vec<PsbEntryInspection>,
    pub psb_serdes_entries: Vec<PsbSerdesEntryInspection>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PswLaneInspection {
    pub lane: u8,
    pub sbr_offset: usize,
    pub raw_value: u8,
    pub ssc_default: u8,
    pub protocol_default: u8,
    pub reserved_bits: u8,
    pub soft_control: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PswBlockInspection {
    pub block: &'static str,
    pub station: &'static str,
    pub offset: u32,
    pub size: u32,
    pub expected_size: u32,
    pub state: String,
    pub trailing_reserved_bits: u16,
    pub write_policy: &'static str,
    pub lanes: Vec<PswLaneInspection>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PswInspection {
    pub schema: &'static str,
    pub sbr_sha256: String,
    pub blocks: Vec<PswBlockInspection>,
}

#[derive(Clone, Copy)]
struct KnownPsbRegister {
    offset: u32,
    key: &'static str,
    name: &'static str,
    expert_writable: bool,
}

const KNOWN_PSB_REGISTERS: &[KnownPsbRegister] = &[
    KnownPsbRegister {
        offset: 0x20c,
        key: "phy_user_test_pattern_0",
        name: "PHY User Test Pattern 0",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0x210,
        key: "phy_user_test_pattern_4",
        name: "PHY User Test Pattern 4",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0x214,
        key: "phy_user_test_pattern_8",
        name: "PHY User Test Pattern 8",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0x218,
        key: "phy_user_test_pattern_12",
        name: "PHY User Test Pattern 12",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0x22c,
        key: "phy_station_chicken_bits",
        name: "PHY Station Chicken Bits",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0x264,
        key: "lane_margin_control_1",
        name: "Lane Margin Control 1",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0x72c,
        key: "gen3_framing_error_disable",
        name: "Gen3 Framing Error Disable",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0x760,
        key: "tic_station_control",
        name: "TIC Station-Based Control",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0xbd4,
        key: "gen3_equalization_tx_coefficient",
        name: "8.0 GT/s Equalization TX Coefficient",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0xbf0,
        key: "port_safety_2",
        name: "Port Safety Register 2",
        expert_writable: true,
    },
    KnownPsbRegister {
        offset: 0xd90,
        key: "reserved_0xd90",
        name: "Reserved",
        expert_writable: false,
    },
];

fn known_psb_register_by_key(key: &str) -> Option<&'static KnownPsbRegister> {
    KNOWN_PSB_REGISTERS
        .iter()
        .find(|register| register.key == key)
}

fn psb_value_mask(byte_mask: u8) -> u32 {
    (0..4).fold(0u32, |mask, byte| {
        if byte_mask & (1 << byte) != 0 {
            mask | (0xff << (byte * 8))
        } else {
            mask
        }
    })
}

#[derive(Deserialize)]
#[serde(untagged)]
enum U32Input {
    Number(u64),
    String(String),
}

fn deserialize_u32<'de, D>(deserializer: D) -> std::result::Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    let input = U32Input::deserialize(deserializer)?;
    let value = match input {
        U32Input::Number(value) => value,
        U32Input::String(value) => {
            let trimmed = value.trim();
            let (digits, radix) = trimmed
                .strip_prefix("0x")
                .or_else(|| trimmed.strip_prefix("0X"))
                .map(|digits| (digits, 16))
                .unwrap_or((trimmed, 10));
            u64::from_str_radix(digits, radix).map_err(serde::de::Error::custom)?
        }
    };
    u32::try_from(value).map_err(|_| serde::de::Error::custom("value exceeds 32 bits"))
}

fn serialize_u32_hex<S>(value: &u32, serializer: S) -> std::result::Result<S::Ok, S::Error>
where
    S: Serializer,
{
    serializer.serialize_str(&format!("{value:#010x}"))
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct StationInspection {
    pub station: u8,
    pub codes: [u8; 4],
    pub layout: Option<StationLayout>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SbrInspection {
    pub schema: &'static str,
    pub format: &'static str,
    pub device: &'static str,
    pub signature: u32,
    pub length: usize,
    pub sha256: String,
    pub checksum: ChecksumInspection,
    pub index_dwords: Vec<u32>,
    pub soc: SocInspection,
    pub blocks: Vec<BlockInspection>,
    pub psb_entries: Vec<PsbEntryInspection>,
    pub psb_serdes_entries: Vec<PsbSerdesEntryInspection>,
    pub stations: Vec<StationInspection>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct StationDifference {
    pub station: u8,
    pub before_codes: [u8; 4],
    pub after_codes: [u8; 4],
    pub before_layout: Option<StationLayout>,
    pub after_layout: Option<StationLayout>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct NamedDifference {
    pub field: &'static str,
    pub before: String,
    pub after: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PsbEntryDifference {
    pub index: usize,
    pub register_key: Option<&'static str>,
    pub register_offset: u32,
    pub descriptor: u32,
    pub before: u32,
    pub after: u32,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct PsbSerdesEntryDifference {
    pub index: usize,
    pub address: u32,
    pub before: u32,
    pub after: u32,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SbrDiffReport {
    pub schema: &'static str,
    pub before_sha256: String,
    pub after_sha256: String,
    pub before_length: usize,
    pub after_length: usize,
    pub named_differences: Vec<NamedDifference>,
    pub station_differences: Vec<StationDifference>,
    pub psb_entry_differences: Vec<PsbEntryDifference>,
    pub psb_serdes_entry_differences: Vec<PsbSerdesEntryDifference>,
    pub byte_differences: Vec<ByteDifference>,
}

#[derive(Clone, Copy)]
struct NamedSocField {
    name: &'static str,
    offset: usize,
    bit_low: u8,
    width: u8,
    writable: bool,
}

#[derive(Clone, Copy)]
struct PortDefaultLocation {
    port_type_offset: usize,
    port_type_bit_low: u8,
    clock_mode_offset: usize,
    clock_mode_bit_low: u8,
}

fn port_default_location(port: u8) -> Option<PortDefaultLocation> {
    match port {
        0..=95 => {
            let group = usize::from(port / 16);
            let bit_low = (port % 16) * 2;
            Some(PortDefaultLocation {
                port_type_offset: 0xc0 + group * 4,
                port_type_bit_low: bit_low,
                clock_mode_offset: 0xe0 + group * 4,
                clock_mode_bit_low: bit_low,
            })
        }
        116 => Some(PortDefaultLocation {
            port_type_offset: 0xdc,
            port_type_bit_low: 8,
            clock_mode_offset: 0xf8,
            clock_mode_bit_low: 24,
        }),
        117 => Some(PortDefaultLocation {
            port_type_offset: 0xdc,
            port_type_bit_low: 10,
            clock_mode_offset: 0xf8,
            clock_mode_bit_low: 26,
        }),
        _ => None,
    }
}

const NAMED_SOC_FIELDS: &[NamedSocField] = &[
    NamedSocField {
        name: "soc.upstream_port",
        offset: 0x5c,
        bit_low: 0,
        width: 8,
        writable: true,
    },
    NamedSocField {
        name: "soc.max_link_speed",
        offset: 0x5c,
        bit_low: 8,
        width: 2,
        writable: true,
    },
    NamedSocField {
        name: "soc.lane_enable_code_raw",
        offset: 0x5c,
        bit_low: 13,
        width: 3,
        writable: false,
    },
    NamedSocField {
        name: "soc.station_dpr_enable_mask",
        offset: 0x68,
        bit_low: 8,
        width: 6,
        writable: false,
    },
    NamedSocField {
        name: "soc.atlas_mode_raw",
        offset: 0x68,
        bit_low: 16,
        width: 2,
        writable: false,
    },
    NamedSocField {
        name: "soc.auto_pcie_link_train_enable",
        offset: 0x68,
        bit_low: 18,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.gen1_compliance_n",
        offset: 0x68,
        bit_low: 19,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.fanout_enable",
        offset: 0x68,
        bit_low: 20,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.pll_bypass_mode",
        offset: 0x68,
        bit_low: 21,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.stp_bypass",
        offset: 0x68,
        bit_low: 22,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station0_pcie_clock_request",
        offset: 0x68,
        bit_low: 24,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station1_pcie_clock_request",
        offset: 0x68,
        bit_low: 25,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station2_pcie_clock_request",
        offset: 0x68,
        bit_low: 26,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station3_pcie_clock_request",
        offset: 0x68,
        bit_low: 27,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.flash_signature_enable",
        offset: 0x68,
        bit_low: 30,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.serial_io_b_clock_output_enable",
        offset: 0x68,
        bit_low: 31,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station0_pcie_clock_enable",
        offset: 0x6c,
        bit_low: 0,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station1_pcie_clock_enable",
        offset: 0x6c,
        bit_low: 1,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station2_pcie_clock_enable",
        offset: 0x6c,
        bit_low: 2,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station3_pcie_clock_enable",
        offset: 0x6c,
        bit_low: 3,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.serial_hot_plug_enable",
        offset: 0x6c,
        bit_low: 12,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.station_clock_sequencing_enable",
        offset: 0x6c,
        bit_low: 13,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.shutdown_ocm",
        offset: 0x6c,
        bit_low: 14,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.hardware_auto_power_save_enable",
        offset: 0x6c,
        bit_low: 15,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.hot_plug_controller_polarity",
        offset: 0x6c,
        bit_low: 27,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.ses_endpoint_disable",
        offset: 0x6c,
        bit_low: 28,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.legacy_plx_i2c_target_enable",
        offset: 0x6c,
        bit_low: 30,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.secure_boot_enable",
        offset: 0x70,
        bit_low: 0,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.watchdog_enable",
        offset: 0x70,
        bit_low: 1,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.extended_pll_lock_wait",
        offset: 0x70,
        bit_low: 2,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.spi_pad_slew",
        offset: 0x70,
        bit_low: 3,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.spi_flash_ecc_check_enable",
        offset: 0x70,
        bit_low: 4,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.secure_rom_ecc_check_disable",
        offset: 0x70,
        bit_low: 5,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.bls_ram_single_bit_ecc_check_disable",
        offset: 0x70,
        bit_low: 6,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.bls_ram_double_bit_ecc_check_disable",
        offset: 0x70,
        bit_low: 7,
        width: 1,
        writable: false,
    },
    // New catalog fields belong below the frozen v1 inspection prefix.
    NamedSocField {
        name: "soc.ethernet_tx_clock_source_select",
        offset: 0x6c,
        bit_low: 5,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.ethernet_tx_clock_divider",
        offset: 0x6c,
        bit_low: 6,
        width: 2,
        writable: false,
    },
    NamedSocField {
        name: "soc.serial_debug_mode_raw",
        offset: 0x6c,
        bit_low: 8,
        width: 2,
        writable: false,
    },
    NamedSocField {
        name: "soc.cpu_address_mode",
        offset: 0x6c,
        bit_low: 10,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.initialize_iop_reset",
        offset: 0x6c,
        bit_low: 11,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.system_counter_frequency_select",
        offset: 0x6c,
        bit_low: 20,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.system_counter_halt_on_debug",
        offset: 0x6c,
        bit_low: 21,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.system_counter_enable",
        offset: 0x6c,
        bit_low: 22,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.aladin_capture_clock_select",
        offset: 0x6c,
        bit_low: 23,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.alternate_d_select_default_raw",
        offset: 0x6c,
        bit_low: 24,
        width: 3,
        writable: false,
    },
    NamedSocField {
        name: "soc.baud_clock_select",
        offset: 0x6c,
        bit_low: 29,
        width: 1,
        writable: false,
    },
    NamedSocField {
        name: "soc.dcsg_scratch1",
        offset: 0x70,
        bit_low: 16,
        width: 8,
        writable: false,
    },
    NamedSocField {
        name: "soc.dcsg_scratch2",
        offset: 0x70,
        bit_low: 24,
        width: 8,
        writable: false,
    },
    NamedSocField {
        name: "soc.customer_scratch1",
        offset: 0x74,
        bit_low: 0,
        width: 8,
        writable: false,
    },
    NamedSocField {
        name: "soc.customer_scratch2",
        offset: 0x74,
        bit_low: 8,
        width: 8,
        writable: false,
    },
    NamedSocField {
        name: "soc.dcsg_configuration",
        offset: 0x74,
        bit_low: 16,
        width: 8,
        writable: false,
    },
    NamedSocField {
        name: "soc.pvtmon_pulse_count_low",
        offset: 0x140,
        bit_low: 0,
        width: 8,
        writable: false,
    },
    NamedSocField {
        name: "soc.pvtmon_pulse_count_high",
        offset: 0x140,
        bit_low: 8,
        width: 3,
        writable: false,
    },
    NamedSocField {
        name: "soc.pvtmon_ring_select",
        offset: 0x140,
        bit_low: 12,
        width: 4,
        writable: false,
    },
];

fn inspection_v1_soc_fields() -> &'static [NamedSocField] {
    &NAMED_SOC_FIELDS[..ATLAS_INSPECTION_V1_SOC_FIELD_COUNT]
}

fn named_soc_field(name: &str) -> Option<NamedSocField> {
    NAMED_SOC_FIELDS
        .iter()
        .copied()
        .find(|field| field.name == name)
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SbrImage {
    bytes: Vec<u8>,
    index: [u32; SBR_INDEX_DWORDS],
    checksum_offset: usize,
}

impl SbrImage {
    pub fn read(path: &Path) -> Result<Self> {
        let bytes = fs::read(path)
            .map_err(|source| Error::io(format!("reading {}", path.display()), source))?;
        Self::parse(bytes)
    }

    pub fn parse(bytes: Vec<u8>) -> Result<Self> {
        let expected = expected_size_from_prefix(&bytes)?;
        if bytes.len() != expected {
            return Err(Error::Format(format!(
                "index describes {expected:#x} bytes, file contains {:#x}",
                bytes.len()
            )));
        }

        let index = parse_index(&bytes)?;
        let checksum_offset = expected - 4;
        let image = Self {
            bytes,
            index,
            checksum_offset,
        };
        image.validate_structure()?;
        Ok(image)
    }

    pub fn parse_prefix(bytes: &[u8]) -> Result<Self> {
        let expected = expected_size_from_prefix(bytes)?;
        if bytes.len() < expected {
            return Err(Error::Format(format!(
                "truncated image: index describes {expected:#x} bytes, only {:#x} available",
                bytes.len()
            )));
        }
        Self::parse(bytes[..expected].to_vec())
    }

    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub fn into_bytes(self) -> Vec<u8> {
        self.bytes
    }

    pub fn signature(&self) -> u32 {
        read_u32(&self.bytes, 0).expect("validated signature")
    }

    pub fn index(&self) -> &[u32; SBR_INDEX_DWORDS] {
        &self.index
    }

    pub fn block(&self, kind: BlockKind) -> Block {
        let (offset_index, size_index) = kind.index_pair();
        Block {
            kind,
            offset: self.index[offset_index],
            size: self.index[size_index],
        }
    }

    pub fn blocks(&self) -> impl Iterator<Item = Block> + '_ {
        BlockKind::ALL.into_iter().map(|kind| self.block(kind))
    }

    pub fn block_dwords(&self, kind: BlockKind) -> Vec<u32> {
        self.block_bytes(kind)
            .chunks_exact(4)
            .map(|dword| u32::from_le_bytes(dword.try_into().expect("four-byte chunk")))
            .collect()
    }

    pub fn psb_entries(&self) -> Vec<PsbEntryInspection> {
        let block = self.block(BlockKind::Psb);
        self.block_bytes(BlockKind::Psb)
            .chunks_exact(8)
            .enumerate()
            .map(|(index, entry)| {
                let value = u32::from_le_bytes(entry[..4].try_into().expect("four-byte PSB value"));
                let descriptor =
                    u32::from_le_bytes(entry[4..].try_into().expect("four-byte PSB descriptor"));
                let register_offset = (descriptor & PSB_REGISTER_WORD_MASK) << 2;
                let known_register = KNOWN_PSB_REGISTERS
                    .iter()
                    .find(|register| register.offset == register_offset);
                PsbEntryInspection {
                    index,
                    sbr_offset: block.offset as usize + index * 8,
                    value,
                    descriptor,
                    register_offset,
                    register_key: known_register.map(|register| register.key),
                    register_name: known_register.map(|register| register.name),
                    expert_writable: known_register
                        .is_some_and(|register| register.expert_writable),
                    write_policy: if known_register.is_some_and(|register| register.expert_writable)
                    {
                        "expert"
                    } else {
                        "read-only"
                    },
                    byte_mask: ((descriptor & PSB_BYTE_MASK_MASK) >> 24) as u8,
                    broadcast: descriptor & PSB_BROADCAST_MASK != 0,
                    reserved_bits: descriptor
                        & !(PSB_REGISTER_WORD_MASK | PSB_BYTE_MASK_MASK | PSB_BROADCAST_MASK),
                }
            })
            .collect()
    }

    pub fn psb_serdes_entries(&self) -> Vec<PsbSerdesEntryInspection> {
        let block = self.block(BlockKind::PsbSerdes);
        self.block_bytes(BlockKind::PsbSerdes)
            .chunks_exact(8)
            .enumerate()
            .map(|(index, entry)| {
                let address =
                    u32::from_le_bytes(entry[..4].try_into().expect("four-byte AXI address"));
                let value = u32::from_le_bytes(entry[4..].try_into().expect("four-byte AXI value"));
                let broadcast_mode = ((address & AXI_BROADCAST_ADDRESS_MASK)
                    == AXI_BROADCAST_ADDRESS_VALUE)
                    .then(|| {
                        AxiBroadcastMode::from_code(
                            ((address & AXI_BROADCAST_MODE_MASK) >> 24) as u8,
                        )
                    });
                PsbSerdesEntryInspection {
                    index,
                    sbr_offset: block.offset as usize + index * 8,
                    address,
                    value,
                    broadcast_mode,
                }
            })
            .collect()
    }

    pub fn entry_inspection(&self) -> SbrEntryInspection {
        SbrEntryInspection {
            schema: ATLAS_ENTRY_INSPECTION_SCHEMA,
            sbr_sha256: sha256_hex(&self.bytes),
            psb_entries: self.psb_entries(),
            psb_serdes_entries: self.psb_serdes_entries(),
        }
    }

    pub fn psw_inspection(&self) -> PswInspection {
        let blocks = BlockKind::PSW
            .into_iter()
            .map(|kind| {
                let block = self.block(kind);
                let bytes = self.block_bytes(kind);
                let lane_count = if kind == BlockKind::Pswx2 {
                    bytes.len().min(2)
                } else {
                    bytes.len()
                };
                let lanes = bytes[..lane_count]
                    .iter()
                    .enumerate()
                    .map(|(lane, value)| PswLaneInspection {
                        lane: lane as u8,
                        sbr_offset: block.offset as usize + lane,
                        raw_value: *value,
                        ssc_default: value & 0x07,
                        protocol_default: (value >> 3) & 0x03,
                        reserved_bits: (value >> 5) & 0x03,
                        soft_control: value & 0x80 != 0,
                    })
                    .collect();
                PswBlockInspection {
                    block: kind.name(),
                    station: kind.psw_station().expect("PSW block has station"),
                    offset: block.offset,
                    size: block.size,
                    expected_size: kind.exact_size().expect("PSW block has exact size"),
                    state: block.state().to_string(),
                    trailing_reserved_bits: if kind == BlockKind::Pswx2 && bytes.len() == 4 {
                        u16::from_le_bytes(bytes[2..4].try_into().expect("two-byte PSWx2 tail"))
                    } else {
                        0
                    },
                    write_policy: "read-only",
                    lanes,
                }
            })
            .collect();
        PswInspection {
            schema: ATLAS_PSW_INSPECTION_SCHEMA,
            sbr_sha256: sha256_hex(&self.bytes),
            blocks,
        }
    }

    pub fn checksum_offset(&self) -> usize {
        self.checksum_offset
    }

    pub fn stored_checksum(&self) -> u32 {
        read_u32(&self.bytes, self.checksum_offset).expect("validated checksum")
    }

    pub fn expected_checksum(&self) -> u8 {
        expected_checksum(&self.bytes[..self.checksum_offset])
    }

    pub fn checksum_valid(&self) -> bool {
        self.stored_checksum() == u32::from(self.expected_checksum())
    }

    pub fn update_checksum(&mut self) {
        let checksum = self.expected_checksum();
        self.bytes[self.checksum_offset..self.checksum_offset + 4]
            .copy_from_slice(&u32::from(checksum).to_le_bytes());
    }

    pub fn upstream_port(&self) -> u8 {
        self.read_bits(UPSTREAM_PORT_START_BIT, 8)
    }

    pub fn max_link_speed_code(&self) -> u8 {
        self.read_bits(MAX_LINK_SPEED_START_BIT, 2)
    }

    pub fn max_link_speed(&self) -> PcieGeneration {
        PcieGeneration::from_code(self.max_link_speed_code())
    }

    pub fn lane_enable_code_raw(&self) -> u8 {
        self.read_bits(LANE_ENABLE_START_BIT, 3)
    }

    pub fn soc_dwords(&self) -> Vec<u32> {
        (SOC_OFFSET..SOC_END)
            .step_by(4)
            .map(|offset| read_u32(&self.bytes, offset).expect("validated SoC settings"))
            .collect()
    }

    pub fn station_codes(&self, station: usize) -> Result<[u8; 4]> {
        if station >= 6 {
            return Err(Error::Usage(format!(
                "Atlas station must be 0 through 5, got {station}"
            )));
        }
        let mut codes = [0u8; 4];
        for (quarter, code) in codes.iter_mut().enumerate() {
            *code = self.read_bits(STATION_CONFIG_START_BIT + (station * 4 + quarter) * 3, 3);
        }
        Ok(codes)
    }

    pub fn inferred_station_layout(&self, station: usize) -> Result<Option<StationLayout>> {
        Ok(match self.station_codes(station)? {
            [0, 0, 0, 0] => Some(StationLayout::X16),
            [1, 1, 1, 1] => Some(StationLayout::X4X4X4X4),
            _ => None,
        })
    }

    pub fn editable_config(&self) -> AtlasConfig {
        AtlasConfig {
            schema: ATLAS_CONFIG_SCHEMA.into(),
            soc: AtlasSocConfig {
                upstream_port: Some(self.upstream_port()),
                max_link_speed: Some(self.max_link_speed()),
            },
            stations: (0..6)
                .map(|station| AtlasStationConfig {
                    station: station as u8,
                    layout: self
                        .inferred_station_layout(station)
                        .expect("fixed station range"),
                })
                .collect(),
            expert_soc_fields: Vec::new(),
            expert_psb_entries: Vec::new(),
            expert_psb_serdes_entries: Vec::new(),
        }
    }

    pub fn expert_soc_field_config(&self, name: &str, value: u8) -> Result<AtlasConfig> {
        self.validate()?;
        let field = named_soc_field(name).ok_or_else(|| {
            Error::Usage(format!(
                "unknown SoC field {name:?}; use `pexctl sbr fields IMAGE` to list known fields"
            ))
        })?;
        if field.writable {
            return Err(Error::Usage(format!(
                "{name:?} has an ordinary typed configuration field; use `pexctl sbr export-config`"
            )));
        }
        let current = self.read_bits(
            field.offset * 8 + usize::from(field.bit_low),
            usize::from(field.width),
        );
        if value == current {
            return Err(Error::Usage(format!(
                "{name:?} already has value {value}; no patch generated"
            )));
        }
        let config = AtlasConfig {
            schema: ATLAS_CONFIG_SCHEMA.into(),
            soc: AtlasSocConfig::default(),
            stations: Vec::new(),
            expert_soc_fields: vec![ExpertSocFieldPatch {
                field: name.into(),
                expected: current,
                value,
            }],
            expert_psb_entries: Vec::new(),
            expert_psb_serdes_entries: Vec::new(),
        };
        config.validate()?;
        Ok(config)
    }

    pub fn expert_psb_entry_config(&self, index: usize, value: u32) -> Result<AtlasConfig> {
        self.validate()?;
        let entries = self.psb_entries();
        let entry = entries.get(index).ok_or_else(|| {
            Error::Usage(format!(
                "PSB entry {index} does not exist; image contains {} entries",
                entries.len()
            ))
        })?;
        if !entry.expert_writable {
            return Err(Error::Safety(format!(
                "PSB entry {index} at register {:#x} has policy {}; no patch generated",
                entry.register_offset, entry.write_policy
            )));
        }
        let config = AtlasConfig {
            schema: ATLAS_CONFIG_SCHEMA.into(),
            soc: AtlasSocConfig::default(),
            stations: Vec::new(),
            expert_soc_fields: Vec::new(),
            expert_psb_entries: vec![ExpertPsbEntryPatch {
                index,
                register_key: entry
                    .register_key
                    .expect("expert-writable PSB entry has a key")
                    .into(),
                expected_descriptor: entry.descriptor,
                expected_value: entry.value,
                value,
            }],
            expert_psb_serdes_entries: Vec::new(),
        };
        config.validate()?;
        Ok(config)
    }

    pub fn expert_psb_serdes_entry_config(&self, index: usize, value: u32) -> Result<AtlasConfig> {
        self.validate()?;
        let entries = self.psb_serdes_entries();
        let entry = entries.get(index).ok_or_else(|| {
            Error::Usage(format!(
                "PSB-SerDes entry {index} does not exist; image contains {} entries",
                entries.len()
            ))
        })?;
        let config = AtlasConfig {
            schema: ATLAS_CONFIG_SCHEMA.into(),
            soc: AtlasSocConfig::default(),
            stations: Vec::new(),
            expert_soc_fields: Vec::new(),
            expert_psb_entries: Vec::new(),
            expert_psb_serdes_entries: vec![ExpertPsbSerdesEntryPatch {
                index,
                expected_address: entry.address,
                expected_value: entry.value,
                value,
            }],
        };
        config.validate()?;
        Ok(config)
    }

    pub fn apply_config(&mut self, config: &AtlasConfig) -> Result<()> {
        self.apply_config_with_policy(config, false)
    }

    pub fn apply_config_with_policy(
        &mut self,
        config: &AtlasConfig,
        allow_expert_fields: bool,
    ) -> Result<()> {
        self.apply_config_with_options(
            config,
            AtlasApplyPolicy {
                allow_expert_soc_fields: allow_expert_fields,
                allow_expert_entries: false,
            },
        )
    }

    pub fn apply_config_with_options(
        &mut self,
        config: &AtlasConfig,
        policy: AtlasApplyPolicy,
    ) -> Result<()> {
        self.validate()?;
        config.validate_with_policy(policy)?;
        for patch in &config.expert_soc_fields {
            let field = named_soc_field(&patch.field).expect("validated expert field");
            let current = self.read_bits(
                field.offset * 8 + usize::from(field.bit_low),
                usize::from(field.width),
            );
            if current != patch.expected {
                return Err(Error::Safety(format!(
                    "expert SoC field {:?} expected {}, but input contains {}; no fields were changed",
                    patch.field, patch.expected, current
                )));
            }
        }
        let psb_entries = self.psb_entries();
        for patch in &config.expert_psb_entries {
            let current = psb_entries.get(patch.index).ok_or_else(|| {
                Error::Safety(format!(
                    "expert PSB entry {} does not exist; input contains {} entries; no fields were changed",
                    patch.index,
                    psb_entries.len()
                ))
            })?;
            if current.descriptor != patch.expected_descriptor {
                return Err(Error::Safety(format!(
                    "expert PSB entry {} expected descriptor {:#010x}, but input contains {:#010x}; no fields were changed",
                    patch.index, patch.expected_descriptor, current.descriptor
                )));
            }
            if current.register_key != Some(patch.register_key.as_str()) {
                return Err(Error::Safety(format!(
                    "expert PSB entry {} expected register key {:?}, but input resolves it as {:?}; no fields were changed",
                    patch.index, patch.register_key, current.register_key
                )));
            }
            if current.value != patch.expected_value {
                return Err(Error::Safety(format!(
                    "expert PSB entry {} expected value {:#010x}, but input contains {:#010x}; no fields were changed",
                    patch.index, patch.expected_value, current.value
                )));
            }
        }
        let psb_serdes_entries = self.psb_serdes_entries();
        for patch in &config.expert_psb_serdes_entries {
            let current = psb_serdes_entries.get(patch.index).ok_or_else(|| {
                Error::Safety(format!(
                    "expert PSB-SerDes entry {} does not exist; input contains {} entries; no fields were changed",
                    patch.index,
                    psb_serdes_entries.len()
                ))
            })?;
            if current.address != patch.expected_address {
                return Err(Error::Safety(format!(
                    "expert PSB-SerDes entry {} expected address {:#010x}, but input contains {:#010x}; no fields were changed",
                    patch.index, patch.expected_address, current.address
                )));
            }
            if current.value != patch.expected_value {
                return Err(Error::Safety(format!(
                    "expert PSB-SerDes entry {} expected value {:#010x}, but input contains {:#010x}; no fields were changed",
                    patch.index, patch.expected_value, current.value
                )));
            }
        }
        if let Some(upstream_port) = config.soc.upstream_port {
            self.write_bits(UPSTREAM_PORT_START_BIT, 8, upstream_port);
        }
        if let Some(max_link_speed) = config.soc.max_link_speed {
            self.write_bits(MAX_LINK_SPEED_START_BIT, 2, max_link_speed.code());
        }
        for entry in &config.stations {
            if let Some(layout) = entry.layout {
                let station = usize::from(entry.station);
                for (quarter, code) in layout.codes().into_iter().enumerate() {
                    self.write_bits(
                        STATION_CONFIG_START_BIT + (station * 4 + quarter) * 3,
                        3,
                        code,
                    );
                }
            }
        }
        for patch in &config.expert_soc_fields {
            let field = named_soc_field(&patch.field).expect("validated expert field");
            self.write_bits(
                field.offset * 8 + usize::from(field.bit_low),
                usize::from(field.width),
                patch.value,
            );
        }
        let psb_offset = self.block(BlockKind::Psb).offset as usize;
        for patch in &config.expert_psb_entries {
            let value_offset = psb_offset + patch.index * 8;
            self.bytes[value_offset..value_offset + 4].copy_from_slice(&patch.value.to_le_bytes());
        }
        let psb_serdes_offset = self.block(BlockKind::PsbSerdes).offset as usize;
        for patch in &config.expert_psb_serdes_entries {
            let value_offset = psb_serdes_offset + patch.index * 8 + 4;
            self.bytes[value_offset..value_offset + 4].copy_from_slice(&patch.value.to_le_bytes());
        }
        self.update_checksum();
        self.validate()
    }

    pub fn set_station_layout(&mut self, station: usize, layout: StationLayout) -> Result<()> {
        if station >= 6 {
            return Err(Error::Usage(format!(
                "Atlas station must be 0 through 5, got {station}"
            )));
        }
        for (quarter, code) in layout.codes().into_iter().enumerate() {
            self.write_bits(
                STATION_CONFIG_START_BIT + (station * 4 + quarter) * 3,
                3,
                code,
            );
        }
        self.update_checksum();
        self.validate_structure()
    }

    fn named_soc_field_inspections(
        &self,
        fields: &[NamedSocField],
    ) -> Vec<NamedSocFieldInspection> {
        fields
            .iter()
            .map(|field| NamedSocFieldInspection {
                name: field.name,
                offset: field.offset,
                bit_low: field.bit_low,
                bit_high: field.bit_low + field.width - 1,
                value: self.read_bits(
                    field.offset * 8 + usize::from(field.bit_low),
                    usize::from(field.width),
                ),
                writable: field.writable,
                write_policy: if field.writable { "ordinary" } else { "expert" },
            })
            .collect()
    }

    pub fn soc_field_inspection(&self) -> SocFieldInspection {
        let mut fields = self.named_soc_field_inspections(NAMED_SOC_FIELDS);
        fields.sort_by_key(|field| (field.offset, field.bit_low));
        SocFieldInspection {
            schema: ATLAS_SOC_FIELD_INSPECTION_SCHEMA,
            sbr_sha256: sha256_hex(&self.bytes),
            fields,
        }
    }

    pub fn port_defaults_inspection(&self) -> PortDefaultsInspection {
        let ports = (0..=95)
            .chain([116, 117])
            .map(|port| {
                let location = port_default_location(port).expect("fixed Atlas port set");
                PortDefaultInspection {
                    port,
                    port_type_raw: self.read_bits(
                        location.port_type_offset * 8 + usize::from(location.port_type_bit_low),
                        2,
                    ),
                    port_type_offset: location.port_type_offset,
                    port_type_bit_low: location.port_type_bit_low,
                    port_type_bit_high: location.port_type_bit_low + 1,
                    clock_mode_raw: self.read_bits(
                        location.clock_mode_offset * 8 + usize::from(location.clock_mode_bit_low),
                        2,
                    ),
                    clock_mode_offset: location.clock_mode_offset,
                    clock_mode_bit_low: location.clock_mode_bit_low,
                    clock_mode_bit_high: location.clock_mode_bit_low + 1,
                    write_policy: "read-only",
                }
            })
            .collect();
        PortDefaultsInspection {
            schema: ATLAS_PORT_DEFAULT_INSPECTION_SCHEMA,
            sbr_sha256: sha256_hex(&self.bytes),
            ports,
        }
    }

    pub fn inspection(&self) -> SbrInspection {
        SbrInspection {
            schema: ATLAS_INSPECTION_SCHEMA,
            format: "Broadcom Atlas SBR",
            device: "PEX88096",
            signature: self.signature(),
            length: self.bytes.len(),
            sha256: sha256_hex(&self.bytes),
            checksum: ChecksumInspection {
                offset: self.checksum_offset,
                stored: self.stored_checksum(),
                expected: self.expected_checksum(),
                valid: self.checksum_valid(),
            },
            index_dwords: self.index.to_vec(),
            soc: SocInspection {
                offset: SOC_OFFSET,
                size: SOC_SIZE,
                sha256: sha256_hex(&self.bytes[SOC_OFFSET..SOC_END]),
                raw_dwords: self.soc_dwords(),
                upstream_port: self.upstream_port(),
                max_link_speed: self.max_link_speed(),
                max_link_speed_code: self.max_link_speed_code(),
                lane_enable_code_raw: self.lane_enable_code_raw(),
                named_fields: self.named_soc_field_inspections(inspection_v1_soc_fields()),
            },
            blocks: self
                .blocks()
                .map(|block| {
                    let bytes = self.block_bytes(block.kind);
                    BlockInspection {
                        name: block.kind.name(),
                        offset: block.offset,
                        size: block.size,
                        state: block.state().to_string(),
                        sha256: (block.state() == BlockState::Enabled).then(|| sha256_hex(bytes)),
                        raw_dwords: self.block_dwords(block.kind),
                    }
                })
                .collect(),
            psb_entries: self.psb_entries(),
            psb_serdes_entries: self.psb_serdes_entries(),
            stations: (0..6)
                .map(|station| StationInspection {
                    station: station as u8,
                    codes: self.station_codes(station).expect("fixed station range"),
                    layout: self
                        .inferred_station_layout(station)
                        .expect("fixed station range"),
                })
                .collect(),
        }
    }

    pub fn diff(&self, after: &Self) -> SbrDiffReport {
        let named_differences = inspection_v1_soc_fields()
            .iter()
            .filter_map(|field| {
                let start_bit = field.offset * 8 + usize::from(field.bit_low);
                let width = usize::from(field.width);
                let before = self.read_bits(start_bit, width);
                let after_value = after.read_bits(start_bit, width);
                (before != after_value).then(|| NamedDifference {
                    field: field.name,
                    before: if field.name == "soc.max_link_speed" {
                        PcieGeneration::from_code(before).to_string()
                    } else {
                        before.to_string()
                    },
                    after: if field.name == "soc.max_link_speed" {
                        PcieGeneration::from_code(after_value).to_string()
                    } else {
                        after_value.to_string()
                    },
                })
            })
            .collect();

        let station_differences = (0..6)
            .filter_map(|station| {
                let before_codes = self.station_codes(station).expect("fixed station range");
                let after_codes = after.station_codes(station).expect("fixed station range");
                (before_codes != after_codes).then(|| StationDifference {
                    station: station as u8,
                    before_codes,
                    after_codes,
                    before_layout: self
                        .inferred_station_layout(station)
                        .expect("fixed station range"),
                    after_layout: after
                        .inferred_station_layout(station)
                        .expect("fixed station range"),
                })
            })
            .collect();

        let psb_entry_differences = self
            .psb_entries()
            .into_iter()
            .zip(after.psb_entries())
            .filter_map(|(before, after)| {
                (before.descriptor == after.descriptor && before.value != after.value).then_some({
                    PsbEntryDifference {
                        index: before.index,
                        register_key: before.register_key,
                        register_offset: before.register_offset,
                        descriptor: before.descriptor,
                        before: before.value,
                        after: after.value,
                    }
                })
            })
            .collect();

        let psb_serdes_entry_differences = self
            .psb_serdes_entries()
            .into_iter()
            .zip(after.psb_serdes_entries())
            .filter_map(|(before, after)| {
                (before.address == after.address && before.value != after.value).then_some({
                    PsbSerdesEntryDifference {
                        index: before.index,
                        address: before.address,
                        before: before.value,
                        after: after.value,
                    }
                })
            })
            .collect();

        SbrDiffReport {
            schema: ATLAS_DIFF_SCHEMA,
            before_sha256: sha256_hex(&self.bytes),
            after_sha256: sha256_hex(&after.bytes),
            before_length: self.bytes.len(),
            after_length: after.bytes.len(),
            named_differences,
            station_differences,
            psb_entry_differences,
            psb_serdes_entry_differences,
            byte_differences: byte_differences(&self.bytes, &after.bytes),
        }
    }

    pub fn validate(&self) -> Result<()> {
        self.validate_structure()?;
        if !self.checksum_valid() {
            return Err(Error::Format(format!(
                "checksum mismatch at {:#x}: stored {:#010x}, expected {:#04x}",
                self.checksum_offset,
                self.stored_checksum(),
                self.expected_checksum()
            )));
        }
        Ok(())
    }

    fn validate_structure(&self) -> Result<()> {
        if self.bytes.len() > MAX_SBR_SIZE {
            return Err(Error::Format(format!(
                "image exceeds Atlas limit of {MAX_SBR_SIZE:#x} bytes"
            )));
        }
        if self.bytes.len() & 3 != 0 {
            return Err(Error::Format("image length is not dword aligned".into()));
        }
        if self.signature() != ATLAS_SIGNATURE_PEX88096 {
            return Err(Error::Format(format!(
                "unsupported signature {:#010x}; expected PEX88096 signature {ATLAS_SIGNATURE_PEX88096:#010x}",
                self.signature()
            )));
        }
        let mut enabled_blocks = Vec::new();
        for block in self.blocks() {
            if block.state() == BlockState::Invalid {
                return Err(Error::Format(format!(
                    "{} has nonzero offset {:#x} and zero size",
                    block.kind.name(),
                    block.offset
                )));
            }
            if let Some(end) = block.end() {
                if block.offset < SOC_END as u32 {
                    return Err(Error::Format(format!(
                        "{} starts at {:#x}, overlapping the fixed header and SoC settings ending at {SOC_END:#x}",
                        block.kind.name(),
                        block.offset
                    )));
                }
                if block.offset % 4 != 0 || block.size % 4 != 0 {
                    return Err(Error::Format(format!(
                        "{} is not dword aligned: offset={:#x} size={:#x}",
                        block.kind.name(),
                        block.offset,
                        block.size
                    )));
                }
                if usize::try_from(end).unwrap_or(usize::MAX) > self.checksum_offset {
                    return Err(Error::Format(format!(
                        "{} ends at {end:#x}, beyond checksum at {:#x}",
                        block.kind.name(),
                        self.checksum_offset
                    )));
                }
                if block.kind.requires_entry_pairs() && block.size % 8 != 0 {
                    return Err(Error::Format(format!(
                        "{} contains value/address pairs but size {:#x} is not 8-byte aligned",
                        block.kind.name(),
                        block.size
                    )));
                }
                if let Some(max_size) = block.kind.max_size() {
                    if block.size > max_size {
                        return Err(Error::Format(format!(
                            "{} size {:#x} exceeds the Atlas limit {max_size:#x}",
                            block.kind.name(),
                            block.size
                        )));
                    }
                }
                if let Some(exact_size) = block.kind.exact_size() {
                    if block.size != exact_size {
                        return Err(Error::Format(format!(
                            "{} enabled size {:#x} does not match the Atlas field database size {exact_size:#x}",
                            block.kind.name(),
                            block.size
                        )));
                    }
                    let bytes = &self.bytes[block.offset as usize..end as usize];
                    let lane_count = if block.kind == BlockKind::Pswx2 {
                        2
                    } else {
                        bytes.len()
                    };
                    for (lane, value) in bytes[..lane_count].iter().enumerate() {
                        if value & 0x60 != 0 {
                            return Err(Error::Format(format!(
                                "{} lane {lane} has nonzero reserved bits in byte {value:#04x}",
                                block.kind.name()
                            )));
                        }
                    }
                    if block.kind == BlockKind::Pswx2 && bytes[2..4] != [0, 0] {
                        return Err(Error::Format(format!(
                            "{} has nonzero reserved bits 31:16",
                            block.kind.name()
                        )));
                    }
                }
                enabled_blocks.push(block);
            }
        }
        enabled_blocks.sort_by_key(|block| block.offset);
        for pair in enabled_blocks.windows(2) {
            let before = pair[0];
            let after = pair[1];
            if after.offset < before.end().expect("enabled block has end") {
                return Err(Error::Format(format!(
                    "{} at {:#x} overlaps {} ending at {:#x}",
                    after.kind.name(),
                    after.offset,
                    before.kind.name(),
                    before.end().expect("enabled block has end")
                )));
            }
        }
        Ok(())
    }

    fn block_bytes(&self, kind: BlockKind) -> &[u8] {
        let block = self.block(kind);
        if block.state() != BlockState::Enabled {
            return &[];
        }
        let start = block.offset as usize;
        let end = start + block.size as usize;
        &self.bytes[start..end]
    }

    fn read_bits(&self, start_bit: usize, width: usize) -> u8 {
        let mut value = 0;
        for bit in 0..width {
            let absolute = start_bit + bit;
            let set = (self.bytes[absolute / 8] >> (absolute % 8)) & 1;
            value |= set << bit;
        }
        value
    }

    fn write_bits(&mut self, start_bit: usize, width: usize, value: u8) {
        for bit in 0..width {
            let absolute = start_bit + bit;
            let mask = 1u8 << (absolute % 8);
            if value & (1 << bit) != 0 {
                self.bytes[absolute / 8] |= mask;
            } else {
                self.bytes[absolute / 8] &= !mask;
            }
        }
    }
}

pub fn expected_size_from_prefix(bytes: &[u8]) -> Result<usize> {
    if bytes.len() < SOC_END {
        return Err(Error::Format(format!(
            "need at least {SOC_END:#x} bytes for Atlas header and SoC settings, got {:#x}",
            bytes.len()
        )));
    }
    let signature = read_u32(bytes, 0)?;
    if signature != ATLAS_SIGNATURE_PEX88096 {
        return Err(Error::Format(format!(
            "unsupported signature {signature:#010x}; expected {ATLAS_SIGNATURE_PEX88096:#010x}"
        )));
    }
    let index = parse_index(bytes)?;
    for (name, offset_index, size_index) in [("rsvd0", 14, 15), ("rsvd1", 20, 21)] {
        if index[offset_index] != 0 {
            return Err(Error::Format(format!(
                "{name} index pair is reserved but has offset {:#x} and size {:#x}",
                index[offset_index], index[size_index]
            )));
        }
    }
    let mut checksum_offset = SOC_END as u32;
    for kind in BlockKind::ALL {
        let (offset_index, size_index) = kind.index_pair();
        let block = Block {
            kind,
            offset: index[offset_index],
            size: index[size_index],
        };
        if block.state() == BlockState::Invalid {
            return Err(Error::Format(format!(
                "{} has nonzero offset {:#x} and zero size",
                kind.name(),
                block.offset
            )));
        }
        if let Some(end) = block.end() {
            checksum_offset = checksum_offset.max(end);
        }
    }
    let expected = usize::try_from(checksum_offset)
        .map_err(|_| Error::Format("SBR size does not fit host address space".into()))?
        .checked_add(4)
        .ok_or_else(|| Error::Format("SBR size overflow".into()))?;
    if expected > MAX_SBR_SIZE {
        return Err(Error::Format(format!(
            "index describes {expected:#x} bytes, exceeding Atlas limit {MAX_SBR_SIZE:#x}"
        )));
    }
    Ok(expected)
}

fn parse_index(bytes: &[u8]) -> Result<[u32; SBR_INDEX_DWORDS]> {
    let mut index = [0u32; SBR_INDEX_DWORDS];
    for (entry, value) in index.iter_mut().enumerate() {
        *value = read_u32(bytes, SBR_INDEX_OFFSET + entry * 4)?;
    }
    Ok(index)
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32> {
    let slice = bytes
        .get(offset..offset + 4)
        .ok_or_else(|| Error::Format(format!("missing dword at offset {offset:#x}")))?;
    Ok(u32::from_le_bytes(
        slice.try_into().expect("slice length checked"),
    ))
}

pub fn expected_checksum(body: &[u8]) -> u8 {
    let sum = body
        .iter()
        .fold(CHECKSUM_SEED, |sum, byte| sum.wrapping_add(*byte));
    0u8.wrapping_sub(sum)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct ByteDifference {
    pub offset: usize,
    pub before: u8,
    pub after: u8,
}

pub fn byte_differences(before: &[u8], after: &[u8]) -> Vec<ByteDifference> {
    let common = before.len().min(after.len());
    let mut differences = Vec::new();
    for offset in 0..common {
        if before[offset] != after[offset] {
            differences.push(ByteDifference {
                offset,
                before: before[offset],
                after: after[offset],
            });
        }
    }
    differences
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

pub fn write_new_file(path: &Path, bytes: &[u8]) -> Result<()> {
    let mut file = match fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
    {
        Ok(file) => file,
        Err(source) if source.kind() == io::ErrorKind::AlreadyExists => {
            return Err(Error::Safety(format!(
                "{} already exists; choose a new output path",
                path.display()
            )));
        }
        Err(source) => {
            return Err(Error::io(format!("creating {}", path.display()), source));
        }
    };
    file.write_all(bytes)
        .map_err(|source| Error::io(format!("writing {}", path.display()), source))?;
    file.sync_all()
        .map_err(|source| Error::io(format!("syncing {}", path.display()), source))
}

pub fn required_confirmation(bdf: &str) -> Result<String> {
    Ok(format!(
        "ERASE-PROGRAM-VERIFY:{}:CS0:SECTOR0",
        normalize_bdf(bdf)?
    ))
}

pub fn verify_config_plan_directory(path: &Path) -> Result<VerifiedAtlasConfigPlan> {
    let directory_metadata = fs::symlink_metadata(path)
        .map_err(|source| Error::io(format!("inspecting {}", path.display()), source))?;
    if directory_metadata.file_type().is_symlink() || !directory_metadata.is_dir() {
        return Err(Error::Safety(format!(
            "{} must be a real plan directory, not a symlink or other file type",
            path.display()
        )));
    }

    let manifest_path = path.join(ATLAS_CONFIG_PLAN_FILE);
    let manifest_bytes =
        read_regular_plan_file(&manifest_path, Some(MAX_CONFIG_PLAN_JSON_SIZE as usize))?;
    let manifest = AtlasConfigPlanManifest::parse_json(&manifest_bytes)?;
    if manifest.to_json_pretty()? != manifest_bytes {
        return Err(Error::Safety(format!(
            "{ATLAS_CONFIG_PLAN_FILE} is not in canonical form"
        )));
    }

    let mut contents = BTreeMap::new();
    for artifact in &manifest.artifacts {
        let artifact_path = path.join(&artifact.name);
        let bytes = read_regular_plan_file(&artifact_path, Some(artifact.size))?;
        if bytes.len() != artifact.size {
            return Err(Error::Safety(format!(
                "plan artifact {:?} has size {:#x}, expected {:#x}",
                artifact.name,
                bytes.len(),
                artifact.size
            )));
        }
        let digest = sha256_hex(&bytes);
        if digest != artifact.sha256 {
            return Err(Error::Safety(format!(
                "plan artifact {:?} SHA-256 is {digest}, expected {}",
                artifact.name, artifact.sha256
            )));
        }
        contents.insert(artifact.name.clone(), bytes);
    }

    let artifact = |name: &str| -> &[u8] {
        contents
            .get(name)
            .expect("manifest validation requires every plan artifact")
    };
    let flash_a = artifact("current-flash-a.bin");
    let flash_b = artifact("current-flash-b.bin");
    if flash_a != flash_b {
        return Err(Error::Safety(
            "plan complete-flash passes do not match".into(),
        ));
    }
    let current_region = artifact("current-region.bin");
    if flash_a.get(..ATLAS_SPI_RECOVERY_REGION_SIZE) != Some(current_region) {
        return Err(Error::Safety(
            "plan current-region.bin is not the prefix of both complete-flash backups".into(),
        ));
    }

    let sbr_offset = usize::try_from(manifest.sbr_offset)
        .map_err(|_| Error::Config("plan SBR offset does not fit host address space".into()))?;
    let current_image = SbrImage::parse_prefix(
        current_region
            .get(sbr_offset..)
            .ok_or_else(|| Error::Config("plan current region ends before its SBR".into()))?,
    )?;
    current_image.validate()?;
    if current_image.bytes() != artifact("current-sbr.bin") {
        return Err(Error::Safety(
            "plan current-sbr.bin does not match the SBR embedded in current-region.bin".into(),
        ));
    }

    let candidate_region = artifact("candidate-region.bin");
    validate_sector0_replacement(current_region, candidate_region)?;
    let candidate_image = SbrImage::parse_prefix(
        candidate_region
            .get(sbr_offset..)
            .ok_or_else(|| Error::Config("plan candidate region ends before its SBR".into()))?,
    )?;
    candidate_image.validate()?;
    if candidate_image.bytes() != artifact("candidate-sbr.bin") {
        return Err(Error::Safety(
            "plan candidate-sbr.bin does not match the SBR embedded in candidate-region.bin".into(),
        ));
    }
    if current_image.bytes().len() != manifest.sbr_size
        || candidate_image.bytes().len() != manifest.sbr_size
    {
        return Err(Error::Safety(
            "plan parsed SBR size disagrees with its manifest".into(),
        ));
    }

    let config = AtlasConfig::parse_json(artifact("applied-config.json"))?;
    config.validate_with_policy(manifest.policy)?;
    if config.to_json_pretty()? != artifact("applied-config.json") {
        return Err(Error::Safety(
            "plan applied-config.json is not in canonical form".into(),
        ));
    }
    let mut reconstructed_candidate = current_image.clone();
    reconstructed_candidate.apply_config_with_options(&config, manifest.policy)?;
    if reconstructed_candidate.bytes() != candidate_image.bytes() {
        return Err(Error::Safety(
            "plan candidate SBR is not the exact result of applying applied-config.json to current-sbr.bin"
                .into(),
        ));
    }

    if json_pretty_bytes(&current_image.inspection())? != artifact("current-inspection.json") {
        return Err(Error::Safety(
            "plan current-inspection.json does not match current-sbr.bin".into(),
        ));
    }
    if json_pretty_bytes(&candidate_image.inspection())? != artifact("candidate-inspection.json") {
        return Err(Error::Safety(
            "plan candidate-inspection.json does not match candidate-sbr.bin".into(),
        ));
    }
    if json_pretty_bytes(&current_image.diff(&candidate_image))? != artifact("diff.json") {
        return Err(Error::Safety(
            "plan diff.json does not match its current and candidate SBRs".into(),
        ));
    }

    Ok(VerifiedAtlasConfigPlan {
        manifest,
        expected_current: current_region.to_vec(),
        candidate: candidate_region.to_vec(),
    })
}

fn read_regular_plan_file(path: &Path, maximum_size: Option<usize>) -> Result<Vec<u8>> {
    let metadata = fs::symlink_metadata(path)
        .map_err(|source| Error::io(format!("inspecting {}", path.display()), source))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(Error::Safety(format!(
            "{} must be a regular file, not a symlink or other file type",
            path.display()
        )));
    }
    let size = usize::try_from(metadata.len())
        .map_err(|_| Error::Safety(format!("{} is too large for this host", path.display())))?;
    if let Some(maximum_size) = maximum_size {
        if size > maximum_size {
            return Err(Error::Safety(format!(
                "{} is {size:#x} bytes, larger than allowed {maximum_size:#x}",
                path.display()
            )));
        }
    }
    fs::read(path).map_err(|source| Error::io(format!("reading {}", path.display()), source))
}

fn json_pretty_bytes<T: Serialize>(value: &T) -> Result<Vec<u8>> {
    let mut bytes = serde_json::to_vec_pretty(value)
        .map_err(|error| Error::Config(format!("serializing JSON: {error}")))?;
    bytes.push(b'\n');
    Ok(bytes)
}

const PLX_DRIVER_PATH: &str = "/dev/plx/PlxSvc";
const PLX_PARAMS_SIZE: usize = 356;
const PLX_KEY_OFFSET: usize = 4;
const PLX_KEY_SIZE: usize = 44;
const PLX_VALUE_OFFSET: usize = 48;
const PLX_STATUS_OK: i32 = 0x200;
const PLX_SDK_VERSION_MAJOR: u8 = 8;
const PLX_SDK_VERSION_MINOR: u8 = 23;
const PLX_IOCTL_DRIVER_VERSION: usize = plx_ioctl(0);
const PLX_IOCTL_PCI_DEVICE_FIND: usize = plx_ioctl(7);
const PLX_IOCTL_MAPPED_REGISTER_READ: usize = plx_ioctl(17);
const PLX_IOCTL_MAPPED_REGISTER_WRITE: usize = plx_ioctl(18);

const ATLAS_SPI_CONTROLLER_OFFSET: u32 = 0x1c_0000;
const SPI_MANUAL_IO_MODE: u32 = ATLAS_SPI_CONTROLLER_OFFSET + 0x7c;
const SPI_MANUAL_READ_DATA: u32 = ATLAS_SPI_CONTROLLER_OFFSET + 0x78;
const SPI_MANUAL_WRITE_DATA: u32 = ATLAS_SPI_CONTROLLER_OFFSET + 0x80;
const SPI_MANUAL_CONTROL_STATUS: u32 = ATLAS_SPI_CONTROLLER_OFFSET + 0x84;
const SPI_CONTROL_LAST: u32 = 1 << 11;
const SPI_CONTROL_WRITE: u32 = 1 << 12;
const SPI_CONTROL_ATOMIC: u32 = 1 << 14;
const SPI_CONTROL_VALID: u32 = 1 << 16;
const SPI_MORE_COMMANDS: u8 = 1 << 0;
const SPI_MORE_DATA: u8 = 1 << 1;
const SPI_CMD_READ_ID: u8 = 0x9f;
const SPI_CMD_ERASE_SECTOR: u8 = 0xd8;
const SPI_CMD_READ: u8 = 0x03;
const SPI_CMD_READ_STATUS_1: u8 = 0x05;
const SPI_CMD_READ_STATUS_2: u8 = 0x35;
const SPI_CMD_READ_STATUS_3: u8 = 0x15;
const SPI_CMD_READ_BLOCK_LOCK: u8 = 0x3d;
const SPI_CMD_WRITE_ENABLE: u8 = 0x06;
const SPI_CMD_WRITE_DISABLE: u8 = 0x04;
const SPI_CMD_WRITE_PAGE: u8 = 0x02;
const SPI_STATUS_1_BUSY: u8 = 1 << 0;
const SPI_STATUS_1_WRITE_ENABLE_LATCH: u8 = 1 << 1;
const SPI_STATUS_1_BLOCK_PROTECT_MASK: u8 = 0b111 << 2;
const SPI_STATUS_1_TOP_BOTTOM: u8 = 1 << 5;
const SPI_STATUS_1_SECTOR_PROTECT: u8 = 1 << 6;
const SPI_STATUS_1_STATUS_REGISTER_PROTECT: u8 = 1 << 7;
const SPI_STATUS_2_STATUS_REGISTER_LOCK: u8 = 1 << 0;
const SPI_STATUS_2_QUAD_ENABLE: u8 = 1 << 1;
const SPI_STATUS_2_SECURITY_REGISTER_LOCK_MASK: u8 = 0b111 << 3;
const SPI_STATUS_2_COMPLEMENT_PROTECT: u8 = 1 << 6;
const SPI_STATUS_2_ERASE_PROGRAM_SUSPENDED: u8 = 1 << 7;
const SPI_STATUS_3_WRITE_PROTECT_SELECTION: u8 = 1 << 2;
const SPI_STATUS_3_OUTPUT_DRIVER_STRENGTH_MASK: u8 = 0b11 << 5;
const SPI_BLOCK_LOCKED: u8 = 1 << 0;
const SPI_PAGE_SIZE: usize = 256;

// Linux _IOWR('P', message, PLX_PARAMS), as defined by Broadcom's
// dual-BSD/GPL PLX SDK 8.23 ABI.
const fn plx_ioctl(message: usize) -> usize {
    (3usize << 30) | (PLX_PARAMS_SIZE << 16) | ((b'P' as usize) << 8) | message
}

#[repr(C, align(4))]
#[derive(Clone)]
struct PlxParams {
    bytes: [u8; PLX_PARAMS_SIZE],
}

const _: [(); PLX_PARAMS_SIZE] = [(); std::mem::size_of::<PlxParams>()];

impl PlxParams {
    fn zeroed() -> Self {
        Self {
            bytes: [0; PLX_PARAMS_SIZE],
        }
    }

    fn return_code(&self) -> i32 {
        i32::from_ne_bytes(self.bytes[..4].try_into().expect("fixed PLX status field"))
    }

    fn key(&self) -> [u8; PLX_KEY_SIZE] {
        self.bytes[PLX_KEY_OFFSET..PLX_KEY_OFFSET + PLX_KEY_SIZE]
            .try_into()
            .expect("fixed PLX key field")
    }

    fn set_key(&mut self, key: &[u8; PLX_KEY_SIZE]) {
        self.bytes[PLX_KEY_OFFSET..PLX_KEY_OFFSET + PLX_KEY_SIZE].copy_from_slice(key);
    }

    fn set_value(&mut self, index: usize, value: u64) {
        let offset = PLX_VALUE_OFFSET + index * 8;
        self.bytes[offset..offset + 8].copy_from_slice(&value.to_ne_bytes());
    }

    fn value(&self, index: usize) -> u64 {
        let offset = PLX_VALUE_OFFSET + index * 8;
        u64::from_ne_bytes(
            self.bytes[offset..offset + 8]
                .try_into()
                .expect("fixed PLX value field"),
        )
    }
}

unsafe extern "C" {
    fn ioctl(fd: i32, request: usize, ...) -> i32;
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SpiFlashStatus {
    pub schema: &'static str,
    pub bdf: String,
    pub jedec_id: [u8; 3],
    pub status_register_1: u8,
    pub status_register_2: u8,
    pub status_register_3: u8,
    pub busy: bool,
    pub write_enable_latch: bool,
    pub block_protect: u8,
    pub top_bottom: bool,
    pub sector_protect: bool,
    pub status_register_protect: bool,
    pub status_register_lock: bool,
    pub quad_enable: bool,
    pub security_register_locks: u8,
    pub complement_protect: bool,
    pub erase_program_suspended: bool,
    pub write_protect_selection_individual: bool,
    pub output_driver_strength: u8,
    pub sector0_lock_register: Option<u8>,
    pub sector0_individual_lock: Option<bool>,
    pub programming_preflight_passed: bool,
    pub refusal_reasons: Vec<String>,
}

impl SpiFlashStatus {
    fn from_registers(
        bdf: &str,
        jedec_id: [u8; 3],
        status_register_1: u8,
        status_register_2: u8,
        status_register_3: u8,
        sector0_lock_register: Option<u8>,
    ) -> Self {
        let busy = status_register_1 & SPI_STATUS_1_BUSY != 0;
        let write_enable_latch = status_register_1 & SPI_STATUS_1_WRITE_ENABLE_LATCH != 0;
        let block_protect = (status_register_1 & SPI_STATUS_1_BLOCK_PROTECT_MASK) >> 2;
        let top_bottom = status_register_1 & SPI_STATUS_1_TOP_BOTTOM != 0;
        let sector_protect = status_register_1 & SPI_STATUS_1_SECTOR_PROTECT != 0;
        let status_register_protect = status_register_1 & SPI_STATUS_1_STATUS_REGISTER_PROTECT != 0;
        let status_register_lock = status_register_2 & SPI_STATUS_2_STATUS_REGISTER_LOCK != 0;
        let quad_enable = status_register_2 & SPI_STATUS_2_QUAD_ENABLE != 0;
        let security_register_locks =
            (status_register_2 & SPI_STATUS_2_SECURITY_REGISTER_LOCK_MASK) >> 3;
        let complement_protect = status_register_2 & SPI_STATUS_2_COMPLEMENT_PROTECT != 0;
        let erase_program_suspended = status_register_2 & SPI_STATUS_2_ERASE_PROGRAM_SUSPENDED != 0;
        let write_protect_selection_individual =
            status_register_3 & SPI_STATUS_3_WRITE_PROTECT_SELECTION != 0;
        let output_driver_strength =
            (status_register_3 & SPI_STATUS_3_OUTPUT_DRIVER_STRENGTH_MASK) >> 5;
        let sector0_individual_lock =
            sector0_lock_register.map(|register| register & SPI_BLOCK_LOCKED != 0);

        let mut refusal_reasons = Vec::new();
        if busy {
            refusal_reasons.push("the flash BUSY bit is set".into());
        }
        if write_enable_latch {
            refusal_reasons
                .push("the flash WEL bit was already set before pexctl issued Write Enable".into());
        }
        if erase_program_suspended {
            refusal_reasons.push("an erase or program operation is suspended".into());
        }
        if write_protect_selection_individual {
            match sector0_individual_lock {
                Some(true) => refusal_reasons.push(
                    "WPS selects individual locks and the sector at address 0 is locked".into(),
                ),
                Some(false) => {}
                None => refusal_reasons.push(
                    "WPS selects individual locks but the sector-0 lock state is unavailable"
                        .into(),
                ),
            }
        } else if block_protect != 0 || complement_protect {
            refusal_reasons.push(format!(
                "WPS selects status-register protection and its BP/CMP configuration is not entirely clear (BP={block_protect:#05b}, CMP={})",
                u8::from(complement_protect)
            ));
        }

        Self {
            schema: SPI_FLASH_STATUS_SCHEMA,
            bdf: bdf.into(),
            jedec_id,
            status_register_1,
            status_register_2,
            status_register_3,
            busy,
            write_enable_latch,
            block_protect,
            top_bottom,
            sector_protect,
            status_register_protect,
            status_register_lock,
            quad_enable,
            security_register_locks,
            complement_protect,
            erase_program_suspended,
            write_protect_selection_individual,
            output_driver_strength,
            sector0_lock_register,
            sector0_individual_lock,
            programming_preflight_passed: refusal_reasons.is_empty(),
            refusal_reasons,
        }
    }

    fn require_programming_preflight(&self) -> Result<()> {
        if self.programming_preflight_passed {
            return Ok(());
        }
        Err(Error::Safety(format!(
            "SPI flash protection/status preflight failed: {}",
            self.refusal_reasons.join("; ")
        )))
    }
}

#[derive(Debug)]
pub struct PlxSvcDevice {
    file: fs::File,
    bdf: String,
    key: [u8; PLX_KEY_SIZE],
    vendor: u16,
    device: u16,
    mapped_flash_size: u64,
}

impl PlxSvcDevice {
    pub fn open(bdf: &str) -> Result<Self> {
        let bdf = normalize_bdf(bdf)?;
        let root = PathBuf::from("/sys/bus/pci/devices").join(&bdf);
        let vendor = read_sysfs_hex_u16(&root.join("vendor"))?;
        let device = read_sysfs_hex_u16(&root.join("device"))?;
        if vendor != 0x1000 {
            return Err(Error::Safety(format!(
                "{bdf} vendor is {vendor:#06x}, not Broadcom/PLX 0x1000"
            )));
        }
        if !matches!(device, 0xc010..=0xc012) {
            return Err(Error::Safety(format!(
                "{bdf} device is {device:#06x}, not a supported Atlas PEX88000-family switch"
            )));
        }
        let resource_path = root.join("resource0");
        let bar_size = fs::metadata(&resource_path)
            .map_err(|source| Error::io(format!("reading {}", resource_path.display()), source))?
            .len();
        let bar_flash_size = bar_size
            .checked_sub(ATLAS_SPI_CS0_MAPPED_OFFSET)
            .ok_or_else(|| {
                Error::Safety(format!(
                    "{bdf} BAR0 size {bar_size:#x} does not contain the Atlas CS0 window at {ATLAS_SPI_CS0_MAPPED_OFFSET:#x}"
                ))
            })?;
        let mapped_flash_size = bar_flash_size.min(
            ATLAS_PORT_REGISTERS_MAPPED_OFFSET
                .checked_sub(ATLAS_SPI_CS0_MAPPED_OFFSET)
                .expect("Atlas port registers follow the SPI window"),
        );

        let address = PciAddress::parse(&bdf)?;
        let file = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(PLX_DRIVER_PATH)
            .map_err(|source| Error::io(format!("opening {PLX_DRIVER_PATH}"), source))?;

        let mut version = PlxParams::zeroed();
        plx_ioctl_call(
            &file,
            PLX_IOCTL_DRIVER_VERSION,
            &mut version,
            "querying driver version",
        )?;
        let packed_version = version.value(0);
        let major = ((packed_version >> 16) & 0xff) as u8;
        let minor = ((packed_version >> 8) & 0xff) as u8;
        if (major, minor) != (PLX_SDK_VERSION_MAJOR, PLX_SDK_VERSION_MINOR) {
            return Err(Error::Safety(format!(
                "{PLX_DRIVER_PATH} ABI is {major}.{minor:02}, expected {PLX_SDK_VERSION_MAJOR}.{PLX_SDK_VERSION_MINOR:02}"
            )));
        }

        let mut find = PlxParams::zeroed();
        find.bytes[PLX_KEY_OFFSET..PLX_KEY_OFFSET + PLX_KEY_SIZE].fill(0xff);
        // PLX_DEVICE_KEY location fields: domain, bus, slot, function.
        find.bytes[PLX_KEY_OFFSET + 4] = address.domain;
        find.bytes[PLX_KEY_OFFSET + 5] = address.bus;
        find.bytes[PLX_KEY_OFFSET + 6] = address.slot;
        find.bytes[PLX_KEY_OFFSET + 7] = address.function;
        find.set_value(0, 0);
        plx_ioctl_call(
            &file,
            PLX_IOCTL_PCI_DEVICE_FIND,
            &mut find,
            "finding PCI device",
        )?;
        require_plx_ok(&find, "finding PCI device")?;
        let key = find.key();
        let found_vendor = u16::from_ne_bytes([key[8], key[9]]);
        let found_device = u16::from_ne_bytes([key[10], key[11]]);
        if (found_vendor, found_device) != (vendor, device) {
            return Err(Error::Safety(format!(
                "{PLX_DRIVER_PATH} resolved {bdf} as {found_vendor:04x}:{found_device:04x}, but sysfs reports {vendor:04x}:{device:04x}"
            )));
        }

        Ok(Self {
            file,
            bdf,
            key,
            vendor,
            device,
            mapped_flash_size,
        })
    }

    pub fn vendor(&self) -> u16 {
        self.vendor
    }

    pub fn device(&self) -> u16 {
        self.device
    }

    pub fn bdf(&self) -> &str {
        &self.bdf
    }

    pub fn mapped_flash_size(&self) -> u64 {
        self.mapped_flash_size
    }

    pub fn mapped_register_read(&self, offset: u32) -> Result<u32> {
        let mut params = PlxParams::zeroed();
        params.set_key(&self.key);
        params.set_value(0, u64::from(offset));
        plx_ioctl_call(
            &self.file,
            PLX_IOCTL_MAPPED_REGISTER_READ,
            &mut params,
            &format!("reading mapped register {offset:#x}"),
        )?;
        require_plx_ok(&params, &format!("reading mapped register {offset:#x}"))?;
        Ok(params.value(1) as u32)
    }

    fn mapped_register_write(&self, offset: u32, value: u32) -> Result<()> {
        let mut params = PlxParams::zeroed();
        params.set_key(&self.key);
        params.set_value(0, u64::from(offset));
        params.set_value(1, u64::from(value));
        plx_ioctl_call(
            &self.file,
            PLX_IOCTL_MAPPED_REGISTER_WRITE,
            &mut params,
            &format!("writing mapped register {offset:#x}"),
        )?;
        require_plx_ok(&params, &format!("writing mapped register {offset:#x}"))
    }

    pub fn read_sbr(&self, flash_offset: u64) -> Result<SbrImage> {
        let prefix_size = align_up_dword(SOC_END);
        let prefix = self.read_flash_mapped(flash_offset, prefix_size)?;
        let image_size = expected_size_from_prefix(&prefix)?;
        let mut bytes = self.read_flash_mapped(flash_offset, align_up_dword(image_size))?;
        bytes.truncate(image_size);
        SbrImage::parse(bytes)
    }

    pub fn read_flash_mapped(&self, flash_offset: u64, size: usize) -> Result<Vec<u8>> {
        if flash_offset & 3 != 0 || size & 3 != 0 {
            return Err(Error::Usage(
                "flash reads require dword-aligned offsets and lengths".into(),
            ));
        }
        let flash_end = flash_offset
            .checked_add(size as u64)
            .ok_or_else(|| Error::Usage("flash read range overflow".into()))?;
        if flash_end > self.mapped_flash_size {
            return Err(Error::Safety(format!(
                "requested flash range {flash_offset:#x}..{flash_end:#x} exceeds the {:#x}-byte CS0 window exposed through BAR0",
                self.mapped_flash_size
            )));
        }
        let mapped_offset = ATLAS_SPI_CS0_MAPPED_OFFSET
            .checked_add(flash_offset)
            .ok_or_else(|| Error::Usage("mapped flash offset overflow".into()))?;
        let mut bytes = vec![0u8; size];
        self.read_mapped_dwords(mapped_offset, &mut bytes)?;
        Ok(bytes)
    }

    pub fn spi_identity(&self) -> Result<[u8; 3]> {
        self.spi_set_serial_mode()?;
        let identity = self.spi_command(0, &[SPI_CMD_READ_ID], 3)?;
        let identity: [u8; 3] = identity.try_into().expect("requested three ID bytes");
        if matches!(identity, [0, 0, 0] | [0xff, 0xff, 0xff]) {
            return Err(Error::Device(format!(
                "SPI CS0 returned implausible JEDEC ID {:02x?}",
                identity
            )));
        }
        Ok(identity)
    }

    pub fn spi_flash_status(&self) -> Result<SpiFlashStatus> {
        let identity = self.spi_identity()?;
        supported_flash_capacity(identity)?;
        self.spi_flash_status_with_identity(identity)
    }

    pub fn read_complete_flash(&self) -> Result<Vec<u8>> {
        let identity = self.spi_identity()?;
        let capacity = supported_flash_capacity(identity)?;
        let mapped_size =
            usize::try_from(self.mapped_flash_size.min(capacity as u64)).map_err(|_| {
                Error::Usage("mapped flash size does not fit host address space".into())
            })?;
        let mut bytes = self.read_flash_mapped(0, mapped_size)?;
        if mapped_size < capacity {
            bytes.extend(self.read_flash_serial_unchecked(mapped_size, capacity - mapped_size)?);
        }
        Ok(bytes)
    }

    pub fn read_flash_serial(&self, flash_offset: u64, size: usize) -> Result<Vec<u8>> {
        let identity = self.spi_identity()?;
        let capacity = supported_flash_capacity(identity)?;
        let flash_offset = usize::try_from(flash_offset).map_err(|_| {
            Error::Usage("serial flash offset does not fit host address space".into())
        })?;
        let end = flash_offset
            .checked_add(size)
            .ok_or_else(|| Error::Usage("serial flash read range overflow".into()))?;
        if end > capacity {
            return Err(Error::Safety(format!(
                "serial read ends at {end:#x}, beyond the {capacity:#x}-byte flash reported by JEDEC ID {:02x?}",
                identity
            )));
        }
        self.read_flash_serial_unchecked(flash_offset, size)
    }

    pub fn program_sector0_recovery_gated(
        &self,
        expected_current: &[u8],
        candidate: &[u8],
        confirmation: &str,
    ) -> Result<()> {
        if (self.vendor, self.device) != (0x1000, 0xc010) {
            return Err(Error::Safety(format!(
                "hardware programming is proven only for PEX88096 1000:c010, not {:04x}:{:04x}",
                self.vendor, self.device
            )));
        }
        let required_confirmation = required_confirmation(&self.bdf)?;
        if confirmation != required_confirmation {
            return Err(Error::Safety(format!(
                "confirmation mismatch; this operation requires --confirm {required_confirmation:?}"
            )));
        }
        validate_sector0_replacement(expected_current, candidate)?;

        let live = self.read_flash_mapped(0, ATLAS_SPI_RECOVERY_REGION_SIZE)?;
        if live != expected_current {
            let mismatch = first_mismatch(&live, expected_current);
            return Err(Error::Safety(format!(
                "live sector 0 does not match the expected-current backup{}",
                mismatch
                    .map(|offset| format!(" (first mismatch at {offset:#x})"))
                    .unwrap_or_default()
            )));
        }

        self.spi_set_serial_mode()?;
        let identity = self.spi_identity()?;
        supported_flash_capacity(identity)?;
        let flash_status = self.spi_flash_status_with_identity(identity)?;
        flash_status.require_programming_preflight()?;

        self.spi_write_enable_checked("sector-0 block erase")?;
        self.spi_command(0, &[SPI_CMD_ERASE_SECTOR, 0, 0, 0], 0)?;
        let status = self.spi_wait_flash_ready(Duration::from_secs(180))?;
        self.require_write_enable_cleared(status, "sector-0 block erase")?;

        for (page_index, page) in candidate[..ATLAS_SPI_ERASE_BLOCK_SIZE]
            .chunks_exact(SPI_PAGE_SIZE)
            .enumerate()
        {
            if page.iter().all(|byte| *byte == 0xff) {
                continue;
            }
            let address = page_index * SPI_PAGE_SIZE;
            self.spi_write_enable_checked(&format!("page program at {address:#x}"))?;
            self.spi_command(
                SPI_MORE_DATA,
                &[
                    SPI_CMD_WRITE_PAGE,
                    ((address >> 16) & 0xff) as u8,
                    ((address >> 8) & 0xff) as u8,
                    (address & 0xff) as u8,
                ],
                0,
            )?;
            self.spi_command(0, page, 0)?;
            let status = self.spi_wait_flash_ready(Duration::from_secs(5))?;
            self.require_write_enable_cleared(status, &format!("page program at {address:#x}"))?;
        }

        let verify = self.read_flash_mapped(0, ATLAS_SPI_RECOVERY_REGION_SIZE)?;
        if verify != candidate {
            let mismatch = first_mismatch(&verify, candidate);
            return Err(Error::Device(format!(
                "sector 0 read-back verification failed{}; do not reset or power-cycle the switch",
                mismatch
                    .map(|offset| format!(" at offset {offset:#x}"))
                    .unwrap_or_default()
            )));
        }
        Ok(())
    }

    fn spi_set_serial_mode(&self) -> Result<()> {
        self.mapped_register_write(SPI_MANUAL_IO_MODE, 0)
    }

    fn read_flash_serial_unchecked(&self, flash_offset: usize, size: usize) -> Result<Vec<u8>> {
        let end = flash_offset
            .checked_add(size)
            .ok_or_else(|| Error::Usage("serial flash read range overflow".into()))?;
        if end > 0x100_0000 {
            return Err(Error::Safety(format!(
                "serial read ends at {end:#x}, beyond the three-byte address space"
            )));
        }
        self.spi_set_serial_mode()?;
        let mut bytes = Vec::with_capacity(size);
        let mut address = flash_offset;
        while address < end {
            let chunk_size = (end - address).min(SPI_PAGE_SIZE);
            bytes.extend(self.spi_command(
                0,
                &[
                    SPI_CMD_READ,
                    ((address >> 16) & 0xff) as u8,
                    ((address >> 8) & 0xff) as u8,
                    (address & 0xff) as u8,
                ],
                chunk_size,
            )?);
            address += chunk_size;
        }
        Ok(bytes)
    }

    fn spi_flash_status_with_identity(&self, identity: [u8; 3]) -> Result<SpiFlashStatus> {
        let status_register_1 = self.spi_read_status_register_1(0)?;
        let status_register_2 = self.spi_command(0, &[SPI_CMD_READ_STATUS_2], 1)?[0];
        let status_register_3 = self.spi_command(0, &[SPI_CMD_READ_STATUS_3], 1)?[0];
        let sector0_lock_register = if status_register_3 & SPI_STATUS_3_WRITE_PROTECT_SELECTION != 0
        {
            Some(self.spi_command(0, &[SPI_CMD_READ_BLOCK_LOCK, 0, 0, 0], 1)?[0])
        } else {
            None
        };
        Ok(SpiFlashStatus::from_registers(
            &self.bdf,
            identity,
            status_register_1,
            status_register_2,
            status_register_3,
            sector0_lock_register,
        ))
    }

    fn spi_write_enable(&self, more_commands: bool) -> Result<()> {
        self.spi_command(
            if more_commands { SPI_MORE_COMMANDS } else { 0 },
            &[SPI_CMD_WRITE_ENABLE],
            0,
        )
        .map(|_| ())
    }

    fn spi_write_enable_checked(&self, operation: &str) -> Result<()> {
        self.spi_write_enable(true)?;
        let status = match self.spi_read_status_register_1(SPI_MORE_COMMANDS) {
            Ok(status) => status,
            Err(error) => {
                let _ = self.spi_command(0, &[SPI_CMD_WRITE_DISABLE], 0);
                return Err(error);
            }
        };
        if status & SPI_STATUS_1_BUSY != 0 || status & SPI_STATUS_1_WRITE_ENABLE_LATCH == 0 {
            let _ = self.spi_command(0, &[SPI_CMD_WRITE_DISABLE], 0);
            return Err(Error::Safety(format!(
                "Write Enable did not produce ready WEL=1 before {operation} (status register 1 is {status:#04x}); the erase/program command was not issued"
            )));
        }
        Ok(())
    }

    fn require_write_enable_cleared(&self, status: u8, operation: &str) -> Result<()> {
        if status & SPI_STATUS_1_WRITE_ENABLE_LATCH == 0 {
            return Ok(());
        }
        let _ = self.spi_command(0, &[SPI_CMD_WRITE_DISABLE], 0);
        Err(Error::Device(format!(
            "WEL remained set after {operation} (status register 1 is {status:#04x}); the flash may have rejected the command; do not reset or power-cycle the switch"
        )))
    }

    fn spi_read_status_register_1(&self, flags: u8) -> Result<u8> {
        Ok(self.spi_command(flags, &[SPI_CMD_READ_STATUS_1], 1)?[0])
    }

    fn spi_wait_flash_ready(&self, timeout: Duration) -> Result<u8> {
        let started = Instant::now();
        loop {
            let status = self.spi_read_status_register_1(0)?;
            if status & SPI_STATUS_1_BUSY == 0 {
                return Ok(status);
            }
            if started.elapsed() >= timeout {
                return Err(Error::Device(format!(
                    "timed out after {} seconds waiting for SPI flash",
                    timeout.as_secs()
                )));
            }
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    fn spi_command(&self, flags: u8, tx: &[u8], rx_size: usize) -> Result<Vec<u8>> {
        if tx.is_empty() {
            return Err(Error::Usage(
                "internal SPI command must contain at least one byte".into(),
            ));
        }

        for (index, chunk) in tx.chunks(4).enumerate() {
            let mut data = [0u8; 4];
            data[..chunk.len()].copy_from_slice(chunk);
            let mut value = u32::from_ne_bytes(data);
            if chunk.len() == 4 {
                value = value.swap_bytes();
            }
            self.mapped_register_write(SPI_MANUAL_WRITE_DATA, value)?;

            let is_last_tx = (index + 1) * 4 >= tx.len();
            let mut control = (chunk.len() as u32 * 8) | SPI_CONTROL_VALID | SPI_CONTROL_WRITE;
            if flags & SPI_MORE_COMMANDS != 0 {
                control |= SPI_CONTROL_ATOMIC;
            }
            if flags & SPI_MORE_DATA == 0 && is_last_tx && rx_size == 0 {
                control |= SPI_CONTROL_LAST;
            }
            self.mapped_register_write(SPI_MANUAL_CONTROL_STATUS, control)?;
            self.spi_wait_controller_ready()?;
        }

        let mut reply = vec![0u8; rx_size];
        let reply_chunks = rx_size.div_ceil(4);
        for (index, chunk) in reply.chunks_mut(4).enumerate() {
            let mut control = (chunk.len() as u32 * 8) | SPI_CONTROL_VALID;
            if index + 1 == reply_chunks {
                control |= SPI_CONTROL_LAST;
            }
            self.mapped_register_write(SPI_MANUAL_CONTROL_STATUS, control)?;
            self.spi_wait_controller_ready()?;
            let value = self.mapped_register_read(SPI_MANUAL_READ_DATA)?;
            let raw = value.to_ne_bytes();
            let chunk_len = chunk.len();
            for (destination, source) in chunk.iter_mut().zip(raw[..chunk_len].iter().rev()) {
                *destination = *source;
            }
        }
        Ok(reply)
    }

    fn spi_wait_controller_ready(&self) -> Result<()> {
        let started = Instant::now();
        loop {
            let value = self.mapped_register_read(SPI_MANUAL_CONTROL_STATUS)?;
            if value & SPI_CONTROL_VALID == 0 {
                return Ok(());
            }
            if started.elapsed() >= Duration::from_secs(1) {
                return Err(Error::Device(
                    "timed out waiting for the Atlas SPI controller".into(),
                ));
            }
        }
    }

    fn read_mapped_dwords(&self, offset: u64, buffer: &mut [u8]) -> Result<()> {
        if offset & 3 != 0 || buffer.len() & 3 != 0 {
            return Err(Error::Usage(
                "mapped reads require dword-aligned offsets and lengths".into(),
            ));
        }
        let end = offset
            .checked_add(buffer.len() as u64)
            .ok_or_else(|| Error::Usage("mapped read range overflow".into()))?;
        if end > u64::from(u32::MAX) + 1 {
            return Err(Error::Usage(format!(
                "mapped read ends at {end:#x}, beyond the PLX 32-bit register address space"
            )));
        }
        for (index, chunk) in buffer.chunks_exact_mut(4).enumerate() {
            let address = u32::try_from(offset + (index * 4) as u64)
                .map_err(|_| Error::Usage("mapped register address overflow".into()))?;
            chunk.copy_from_slice(&self.mapped_register_read(address)?.to_ne_bytes());
        }
        Ok(())
    }
}

pub fn validate_sector0_replacement(expected_current: &[u8], candidate: &[u8]) -> Result<()> {
    if expected_current.len() != ATLAS_SPI_RECOVERY_REGION_SIZE
        || candidate.len() != ATLAS_SPI_RECOVERY_REGION_SIZE
    {
        return Err(Error::Safety(format!(
            "sector 0 recovery images must both be exactly {ATLAS_SPI_RECOVERY_REGION_SIZE:#x} bytes"
        )));
    }
    if expected_current == candidate {
        return Err(Error::Safety(
            "candidate is identical to expected current sector".into(),
        ));
    }

    let sbr_offset = SBR_FLASH_OFFSET as usize;
    let current_sbr = SbrImage::parse_prefix(&expected_current[sbr_offset..])?;
    current_sbr.validate()?;
    let candidate_sbr = SbrImage::parse_prefix(&candidate[sbr_offset..])?;
    candidate_sbr.validate()?;
    if current_sbr.bytes().len() != candidate_sbr.bytes().len() {
        return Err(Error::Safety(format!(
            "candidate SBR length {:#x} differs from current length {:#x}",
            candidate_sbr.bytes().len(),
            current_sbr.bytes().len()
        )));
    }
    let sbr_end = sbr_offset + current_sbr.bytes().len();
    if let Some(offset) =
        expected_current
            .iter()
            .zip(candidate)
            .enumerate()
            .find_map(|(offset, (before, after))| {
                (before != after && !(sbr_offset..sbr_end).contains(&offset)).then_some(offset)
            })
    {
        return Err(Error::Safety(format!(
            "candidate changes byte {offset:#x} outside the validated SBR range {sbr_offset:#x}..{sbr_end:#x}"
        )));
    }
    if let Some(offset) = expected_current
        .iter()
        .zip(candidate)
        .take(ATLAS_SPI_RECOVERY_REGION_SIZE)
        .enumerate()
        .find_map(|(offset, (before, after))| {
            (before != after && offset >= ATLAS_SPI_ERASE_BLOCK_SIZE).then_some(offset)
        })
    {
        return Err(Error::Safety(format!(
            "candidate changes byte {offset:#x} beyond the one {ATLAS_SPI_ERASE_BLOCK_SIZE:#x}-byte block programmed by this writer"
        )));
    }
    Ok(())
}

fn supported_flash_capacity(identity: [u8; 3]) -> Result<usize> {
    if identity != [0xef, 0x60, 0x18] {
        return Err(Error::Safety(format!(
            "unsupported SPI CS0 JEDEC ID {:02x?}; complete-flash geometry is proven only for EF 60 18",
            identity
        )));
    }
    Ok(1usize << identity[2])
}

fn first_mismatch(left: &[u8], right: &[u8]) -> Option<usize> {
    left.iter()
        .zip(right)
        .position(|(left, right)| left != right)
        .or_else(|| (left.len() != right.len()).then_some(left.len().min(right.len())))
}

fn plx_ioctl_call(
    file: &fs::File,
    request: usize,
    params: &mut PlxParams,
    operation: &str,
) -> Result<()> {
    // SAFETY: `params` is exactly the 356-byte, 4-byte-aligned PLX_PARAMS
    // buffer encoded in `request`, and remains live and writable for the call.
    let result = unsafe { ioctl(file.as_raw_fd(), request, params as *mut PlxParams) };
    if result < 0 {
        return Err(Error::io(operation, io::Error::last_os_error()));
    }
    Ok(())
}

fn require_plx_ok(params: &PlxParams, operation: &str) -> Result<()> {
    let status = params.return_code();
    if status != PLX_STATUS_OK {
        return Err(Error::Device(format!(
            "{operation} returned {} ({status:#x})",
            plx_status_name(status)
        )));
    }
    Ok(())
}

fn plx_status_name(status: i32) -> &'static str {
    match status {
        0x200 => "ok",
        0x201 => "failed",
        0x203 => "unsupported",
        0x204 => "no driver",
        0x205 => "invalid object",
        0x206 => "version mismatch",
        0x207 => "invalid offset",
        0x208 => "invalid data",
        0x209 => "invalid size",
        0x20a => "invalid address",
        0x20b => "invalid access",
        0x20c => "insufficient resources",
        0x20d => "timeout",
        0x218 => "not found",
        _ => "unknown PLX status",
    }
}

const fn align_up_dword(value: usize) -> usize {
    (value + 3) & !3
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct PciAddress {
    domain: u8,
    bus: u8,
    slot: u8,
    function: u8,
}

impl PciAddress {
    fn parse(bdf: &str) -> Result<Self> {
        let domain = u16::from_str_radix(&bdf[0..4], 16)
            .map_err(|_| Error::Usage(format!("invalid PCI domain in {bdf:?}")))?;
        let domain = u8::try_from(domain).map_err(|_| {
            Error::Usage(format!(
                "PCI domain in {bdf:?} exceeds the PLX SDK's 8-bit field"
            ))
        })?;
        Ok(Self {
            domain,
            bus: u8::from_str_radix(&bdf[5..7], 16)
                .map_err(|_| Error::Usage(format!("invalid PCI bus in {bdf:?}")))?,
            slot: u8::from_str_radix(&bdf[8..10], 16)
                .map_err(|_| Error::Usage(format!("invalid PCI slot in {bdf:?}")))?,
            function: u8::from_str_radix(&bdf[11..12], 16)
                .map_err(|_| Error::Usage(format!("invalid PCI function in {bdf:?}")))?,
        })
    }
}

fn read_sysfs_hex_u16(path: &Path) -> Result<u16> {
    let value = fs::read_to_string(path)
        .map_err(|source| Error::io(format!("reading {}", path.display()), source))?;
    let value = value.trim().trim_start_matches("0x");
    u16::from_str_radix(value, 16).map_err(|_| {
        Error::Format(format!(
            "{} does not contain a hexadecimal u16",
            path.display()
        ))
    })
}

pub fn normalize_bdf(value: &str) -> Result<String> {
    let value = value.trim();
    let normalized = if value.matches(':').count() == 1 {
        format!("0000:{value}")
    } else {
        value.to_string()
    };
    let bytes = normalized.as_bytes();
    let valid = bytes.len() == 12
        && bytes[4] == b':'
        && bytes[7] == b':'
        && bytes[10] == b'.'
        && normalized
            .chars()
            .enumerate()
            .all(|(index, ch)| matches!(index, 4 | 7 | 10) || ch.is_ascii_hexdigit());
    if !valid {
        return Err(Error::Usage(format!(
            "invalid PCI BDF {value:?}; expected DDDD:BB:DD.F or BB:DD.F"
        )));
    }
    Ok(normalized.to_ascii_lowercase())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn minimal_image(codes: [[u8; 4]; 6]) -> SbrImage {
        let mut bytes = vec![0u8; SOC_END + 4];
        bytes[..4].copy_from_slice(&ATLAS_SIGNATURE_PEX88096.to_le_bytes());
        let checksum = expected_checksum(&bytes[..SOC_END]);
        bytes[SOC_END..].copy_from_slice(&u32::from(checksum).to_le_bytes());
        let mut image = SbrImage::parse(bytes).unwrap();
        for (station, station_codes) in codes.into_iter().enumerate() {
            for (quarter, code) in station_codes.into_iter().enumerate() {
                image.write_bits(
                    STATION_CONFIG_START_BIT + (station * 4 + quarter) * 3,
                    3,
                    code,
                );
            }
        }
        image.update_checksum();
        image
    }

    fn image_with_entry_blocks() -> SbrImage {
        fn write_dword(bytes: &mut [u8], offset: usize, value: u32) {
            bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
        }

        let psb_offset = SOC_END;
        let psb_size = 16usize;
        let psb_serdes_offset = psb_offset + psb_size;
        let psb_serdes_size = 16usize;
        let checksum_offset = psb_serdes_offset + psb_serdes_size;
        let mut bytes = vec![0u8; checksum_offset + 4];
        bytes[..4].copy_from_slice(&ATLAS_SIGNATURE_PEX88096.to_le_bytes());

        write_dword(&mut bytes, SBR_INDEX_OFFSET, psb_offset as u32);
        write_dword(&mut bytes, SBR_INDEX_OFFSET + 4, psb_size as u32);
        write_dword(
            &mut bytes,
            SBR_INDEX_OFFSET + 18 * 4,
            psb_serdes_offset as u32,
        );
        write_dword(
            &mut bytes,
            SBR_INDEX_OFFSET + 19 * 4,
            psb_serdes_size as u32,
        );

        write_dword(&mut bytes, psb_offset, 0x0604_2019);
        write_dword(&mut bytes, psb_offset + 4, 0x1b00_0083);
        write_dword(&mut bytes, psb_offset + 8, 0x81c0_a805);
        write_dword(&mut bytes, psb_offset + 12, 0x0f00_02f5);

        write_dword(&mut bytes, psb_serdes_offset, 0x7200_1234);
        write_dword(&mut bytes, psb_serdes_offset + 4, 0x0000_001f);
        write_dword(&mut bytes, psb_serdes_offset + 8, 0x6041_0064);
        write_dword(&mut bytes, psb_serdes_offset + 12, 0x0000_007f);

        let checksum = expected_checksum(&bytes[..checksum_offset]);
        bytes[checksum_offset..checksum_offset + 4]
            .copy_from_slice(&u32::from(checksum).to_le_bytes());
        SbrImage::parse(bytes).unwrap()
    }

    fn image_with_psw_blocks() -> SbrImage {
        fn write_dword(bytes: &mut [u8], offset: usize, value: u32) {
            bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
        }

        let psw0_offset = SOC_END;
        let psw0_size = 16usize;
        let pswx2_offset = psw0_offset + psw0_size;
        let pswx2_size = 4usize;
        let checksum_offset = pswx2_offset + pswx2_size;
        let mut bytes = vec![0u8; checksum_offset + 4];
        bytes[..4].copy_from_slice(&ATLAS_SIGNATURE_PEX88096.to_le_bytes());

        write_dword(&mut bytes, SBR_INDEX_OFFSET + 2 * 4, psw0_offset as u32);
        write_dword(&mut bytes, SBR_INDEX_OFFSET + 3 * 4, psw0_size as u32);
        write_dword(&mut bytes, SBR_INDEX_OFFSET + 16 * 4, pswx2_offset as u32);
        write_dword(&mut bytes, SBR_INDEX_OFFSET + 17 * 4, pswx2_size as u32);

        bytes[psw0_offset..psw0_offset + psw0_size].fill(0x10);
        bytes[psw0_offset + 1] = 0x9d;
        bytes[pswx2_offset..pswx2_offset + pswx2_size].copy_from_slice(&[0x08, 0x87, 0, 0]);

        let checksum = expected_checksum(&bytes[..checksum_offset]);
        bytes[checksum_offset..checksum_offset + 4]
            .copy_from_slice(&u32::from(checksum).to_le_bytes());
        SbrImage::parse(bytes).unwrap()
    }

    fn create_config_plan_fixture() -> PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};

        static NEXT_PLAN: AtomicU64 = AtomicU64::new(0);
        let directory = std::env::temp_dir().join(format!(
            "pexctl-plan-test-{}-{}",
            std::process::id(),
            NEXT_PLAN.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&directory).unwrap();

        let current_sbr = minimal_image([[0; 4]; 6]);
        let config = AtlasConfig::station_layout(4, StationLayout::X4X4X4X4).unwrap();
        let mut candidate_sbr = current_sbr.clone();
        candidate_sbr.apply_config(&config).unwrap();

        let flash_size = 1usize << 24;
        let mut current_flash = vec![0xff; flash_size];
        let sbr_offset = SBR_FLASH_OFFSET as usize;
        current_flash[sbr_offset..sbr_offset + current_sbr.bytes().len()]
            .copy_from_slice(current_sbr.bytes());
        let current_region = current_flash[..ATLAS_SPI_RECOVERY_REGION_SIZE].to_vec();
        let mut candidate_region = current_region.clone();
        candidate_region[sbr_offset..sbr_offset + candidate_sbr.bytes().len()]
            .copy_from_slice(candidate_sbr.bytes());

        let files = vec![
            ("current-flash-a.bin", current_flash.clone()),
            ("current-flash-b.bin", current_flash),
            ("current-region.bin", current_region),
            ("current-sbr.bin", current_sbr.bytes().to_vec()),
            ("candidate-region.bin", candidate_region),
            ("candidate-sbr.bin", candidate_sbr.bytes().to_vec()),
            ("applied-config.json", config.to_json_pretty().unwrap()),
            (
                "current-inspection.json",
                json_pretty_bytes(&current_sbr.inspection()).unwrap(),
            ),
            (
                "candidate-inspection.json",
                json_pretty_bytes(&candidate_sbr.inspection()).unwrap(),
            ),
            (
                "diff.json",
                json_pretty_bytes(&current_sbr.diff(&candidate_sbr)).unwrap(),
            ),
            (
                "MANIFEST.txt",
                b"test-only human-readable plan summary\n".to_vec(),
            ),
        ];
        let manifest = AtlasConfigPlanManifest::new(
            "0000:c4:00.0",
            0x1000,
            0xc010,
            [0xef, 0x60, 0x18],
            flash_size,
            current_sbr.bytes().len(),
            AtlasApplyPolicy::default(),
            files
                .iter()
                .map(|(name, bytes)| AtlasConfigPlanArtifact::from_bytes(name, bytes))
                .collect(),
        )
        .unwrap();
        for (name, bytes) in files {
            fs::write(directory.join(name), bytes).unwrap();
        }
        fs::write(
            directory.join(ATLAS_CONFIG_PLAN_FILE),
            manifest.to_json_pretty().unwrap(),
        )
        .unwrap();
        directory
    }

    #[test]
    fn verifies_complete_config_plan_and_rejects_semantic_or_symlink_tampering() {
        let directory = create_config_plan_fixture();
        let verified = verify_config_plan_directory(&directory).unwrap();
        assert_eq!(verified.manifest().bdf, "0000:c4:00.0");
        assert_eq!(
            verified.expected_current().len(),
            ATLAS_SPI_RECOVERY_REGION_SIZE
        );
        validate_sector0_replacement(verified.expected_current(), verified.candidate()).unwrap();

        let manifest_path = directory.join(ATLAS_CONFIG_PLAN_FILE);
        let diff_path = directory.join("diff.json");
        let original_diff = fs::read(&diff_path).unwrap();
        let forged_diff = b"{}\n";
        fs::write(&diff_path, forged_diff).unwrap();
        let mut manifest =
            AtlasConfigPlanManifest::parse_json(&fs::read(&manifest_path).unwrap()).unwrap();
        manifest.pci_device = 0xc011;
        assert!(manifest.validate().is_err());
        manifest.pci_device = 0xc010;
        let artifact = manifest
            .artifacts
            .iter_mut()
            .find(|artifact| artifact.name == "diff.json")
            .unwrap();
        *artifact = AtlasConfigPlanArtifact::from_bytes("diff.json", forged_diff);
        fs::write(&manifest_path, json_pretty_bytes(&manifest).unwrap()).unwrap();
        let error = verify_config_plan_directory(&directory)
            .unwrap_err()
            .to_string();
        assert!(error.contains("diff.json does not match"));

        fs::write(&diff_path, &original_diff).unwrap();
        let artifact = manifest
            .artifacts
            .iter_mut()
            .find(|artifact| artifact.name == "diff.json")
            .unwrap();
        *artifact = AtlasConfigPlanArtifact::from_bytes("diff.json", &original_diff);
        fs::write(&manifest_path, json_pretty_bytes(&manifest).unwrap()).unwrap();
        verify_config_plan_directory(&directory).unwrap();

        let real_diff_path = directory.join("real-diff.json");
        fs::rename(&diff_path, &real_diff_path).unwrap();
        std::os::unix::fs::symlink("real-diff.json", &diff_path).unwrap();
        let error = verify_config_plan_directory(&directory)
            .unwrap_err()
            .to_string();
        assert!(error.contains("must be a regular file"));

        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn parses_and_validates_minimal_image() {
        let image = minimal_image([[0; 4]; 6]);
        image.validate().unwrap();
        assert_eq!(image.signature(), ATLAS_SIGNATURE_PEX88096);
        assert_eq!(image.bytes().len(), SOC_END + 4);
        assert_eq!(
            image.inferred_station_layout(4).unwrap(),
            Some(StationLayout::X16)
        );
    }

    #[test]
    fn decodes_psb_and_psb_serdes_entry_pairs() {
        let image = image_with_entry_blocks();
        image.validate().unwrap();

        let psb = image.psb_entries();
        assert_eq!(psb.len(), 2);
        assert_eq!(psb[0].sbr_offset, SOC_END);
        assert_eq!(psb[0].value, 0x0604_2019);
        assert_eq!(psb[0].descriptor, 0x1b00_0083);
        assert_eq!(psb[0].register_offset, 0x20c);
        assert_eq!(psb[0].register_key, Some("phy_user_test_pattern_0"));
        assert_eq!(psb[0].register_name, Some("PHY User Test Pattern 0"));
        assert!(psb[0].expert_writable);
        assert_eq!(psb[0].write_policy, "expert");
        assert_eq!(psb[0].byte_mask, 0xb);
        assert!(psb[0].broadcast);
        assert_eq!(psb[0].reserved_bits, 0);
        assert_eq!(psb[1].register_offset, 0xbd4);
        assert!(!psb[1].broadcast);

        let serdes = image.psb_serdes_entries();
        assert_eq!(serdes.len(), 2);
        assert_eq!(serdes[0].sbr_offset, SOC_END + 16);
        assert_eq!(serdes[0].address, 0x7200_1234);
        assert_eq!(serdes[0].value, 0x1f);
        assert_eq!(serdes[0].broadcast_mode, Some(AxiBroadcastMode::Station));
        assert_eq!(serdes[1].broadcast_mode, None);

        let inspection = image.inspection();
        assert_eq!(inspection.psb_entries, psb);
        assert_eq!(inspection.psb_serdes_entries, serdes);
        assert_eq!(
            inspection.blocks[0].raw_dwords,
            vec![0x0604_2019, 0x1b00_0083, 0x81c0_a805, 0x0f00_02f5]
        );
        assert!(inspection.blocks[0].sha256.is_some());
    }

    #[test]
    fn decodes_vendor_defined_psw_lane_fields_and_ignored_blocks() {
        let image = image_with_psw_blocks();
        image.validate().unwrap();

        let inspection = image.psw_inspection();
        assert_eq!(inspection.schema, ATLAS_PSW_INSPECTION_SCHEMA);
        assert_eq!(inspection.blocks.len(), 7);

        let psw0 = &inspection.blocks[0];
        assert_eq!(psw0.block, "psw0");
        assert_eq!(psw0.station, "0");
        assert_eq!(psw0.state, "enabled");
        assert_eq!(psw0.expected_size, 16);
        assert_eq!(psw0.lanes.len(), 16);
        assert_eq!(psw0.lanes[0].raw_value, 0x10);
        assert_eq!(psw0.lanes[0].ssc_default, 0);
        assert_eq!(psw0.lanes[0].protocol_default, 2);
        assert!(!psw0.lanes[0].soft_control);
        assert_eq!(psw0.lanes[1].ssc_default, 5);
        assert_eq!(psw0.lanes[1].protocol_default, 3);
        assert!(psw0.lanes[1].soft_control);
        assert_eq!(psw0.lanes[1].reserved_bits, 0);

        assert_eq!(inspection.blocks[1].state, "end");
        assert!(inspection.blocks[1].lanes.is_empty());

        let pswx2 = &inspection.blocks[6];
        assert_eq!(pswx2.station, "x2");
        assert_eq!(pswx2.expected_size, 4);
        assert_eq!(pswx2.lanes.len(), 2);
        assert_eq!(pswx2.lanes[0].protocol_default, 1);
        assert_eq!(pswx2.lanes[1].ssc_default, 7);
        assert!(pswx2.lanes[1].soft_control);
        assert_eq!(pswx2.trailing_reserved_bits, 0);
    }

    #[test]
    fn rejects_enabled_psw_size_and_reserved_bit_violations() {
        let image = image_with_psw_blocks();
        let checksum_offset = image.checksum_offset();

        let mut wrong_size = image.bytes().to_vec();
        wrong_size[SBR_INDEX_OFFSET + 3 * 4..SBR_INDEX_OFFSET + 4 * 4]
            .copy_from_slice(&12u32.to_le_bytes());
        let checksum = expected_checksum(&wrong_size[..checksum_offset]);
        wrong_size[checksum_offset..checksum_offset + 4]
            .copy_from_slice(&u32::from(checksum).to_le_bytes());
        let error = SbrImage::parse(wrong_size).unwrap_err().to_string();
        assert!(error.contains("psw0 enabled size"));

        let mut reserved_lane = image.bytes().to_vec();
        reserved_lane[SOC_END] |= 0x20;
        let checksum = expected_checksum(&reserved_lane[..checksum_offset]);
        reserved_lane[checksum_offset..checksum_offset + 4]
            .copy_from_slice(&u32::from(checksum).to_le_bytes());
        let error = SbrImage::parse(reserved_lane).unwrap_err().to_string();
        assert!(error.contains("psw0 lane 0 has nonzero reserved bits"));

        let mut reserved_tail = image.bytes().to_vec();
        reserved_tail[SOC_END + 16 + 2] = 1;
        let checksum = expected_checksum(&reserved_tail[..checksum_offset]);
        reserved_tail[checksum_offset..checksum_offset + 4]
            .copy_from_slice(&u32::from(checksum).to_le_bytes());
        let error = SbrImage::parse(reserved_tail).unwrap_err().to_string();
        assert!(error.contains("pswx2 has nonzero reserved bits 31:16"));
    }

    #[test]
    fn expert_entry_patches_require_identity_expectations_and_opt_in() {
        let original = image_with_entry_blocks();
        let config = AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_psb_entries": [
                    {
                        "index": 0,
                        "register_key": "phy_user_test_pattern_0",
                        "expected_descriptor": "0x1b000083",
                        "expected_value": "0x06042019",
                        "value": "0x06042018"
                    }
                ],
                "expert_psb_serdes_entries": [
                    {
                        "index": 0,
                        "expected_address": "0x72001234",
                        "expected_value": 31,
                        "value": "0x0000001e"
                    }
                ]
            }"#,
        )
        .unwrap();
        let serialized = String::from_utf8(config.to_json_pretty().unwrap()).unwrap();
        assert!(serialized.contains("\"expected_value\": \"0x06042019\""));
        assert!(serialized.contains("\"expected_address\": \"0x72001234\""));

        let mut without_opt_in = original.clone();
        assert!(without_opt_in.apply_config(&config).is_err());
        assert_eq!(without_opt_in, original);

        let mut candidate = original.clone();
        candidate
            .apply_config_with_options(
                &config,
                AtlasApplyPolicy {
                    allow_expert_soc_fields: false,
                    allow_expert_entries: true,
                },
            )
            .unwrap();
        candidate.validate().unwrap();
        assert_eq!(candidate.psb_entries()[0].value, 0x0604_2018);
        assert_eq!(candidate.psb_entries()[0].descriptor, 0x1b00_0083);
        assert_eq!(candidate.psb_serdes_entries()[0].address, 0x7200_1234);
        assert_eq!(candidate.psb_serdes_entries()[0].value, 0x1e);

        let report = original.diff(&candidate);
        assert_eq!(report.psb_entry_differences.len(), 1);
        assert_eq!(report.psb_entry_differences[0].index, 0);
        assert_eq!(report.psb_serdes_entry_differences.len(), 1);
        assert_eq!(report.psb_serdes_entry_differences[0].index, 0);
        let expected_offsets = [SOC_END, SOC_END + 16 + 4, SOC_END + 32];
        assert!(report
            .byte_differences
            .iter()
            .all(|difference| expected_offsets.contains(&difference.offset)));

        let mismatch = AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_psb_entries": [
                    {
                        "index": 0,
                        "register_key": "phy_user_test_pattern_0",
                        "expected_descriptor": "0x1b000083",
                        "expected_value": "0x06042018",
                        "value": "0x06042017"
                    }
                ]
            }"#,
        )
        .unwrap();
        let mut unchanged = original.clone();
        assert!(unchanged
            .apply_config_with_options(
                &mismatch,
                AtlasApplyPolicy {
                    allow_expert_soc_fields: false,
                    allow_expert_entries: true,
                },
            )
            .is_err());
        assert_eq!(unchanged, original);

        let cross_block_mismatch = AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_psb_entries": [
                    {
                        "index": 0,
                        "register_key": "phy_user_test_pattern_0",
                        "expected_descriptor": "0x1b000083",
                        "expected_value": "0x06042019",
                        "value": "0x06042018"
                    }
                ],
                "expert_psb_serdes_entries": [
                    {
                        "index": 0,
                        "expected_address": "0x72001234",
                        "expected_value": "0x00000020",
                        "value": "0x0000001e"
                    }
                ]
            }"#,
        )
        .unwrap();
        let mut atomically_unchanged = original.clone();
        assert!(atomically_unchanged
            .apply_config_with_options(
                &cross_block_mismatch,
                AtlasApplyPolicy {
                    allow_expert_soc_fields: false,
                    allow_expert_entries: true,
                },
            )
            .is_err());
        assert_eq!(atomically_unchanged, original);
    }

    #[test]
    fn expert_entry_config_rejects_ambiguous_or_unwritable_patches() {
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_psb_entries": [{
                    "index": 0,
                    "register_key": "not_a_register",
                    "expected_descriptor": "0x1b000083",
                    "expected_value": 1,
                    "value": 0
                }]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_psb_entries": [{
                    "index": 8,
                    "register_key": "reserved_0xd90",
                    "expected_descriptor": "0x1f000364",
                    "expected_value": 1,
                    "value": 0
                }]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_psb_entries": [{
                    "index": 0,
                    "register_key": "phy_user_test_pattern_0",
                    "expected_descriptor": "0x0f000084",
                    "expected_value": 1,
                    "value": 0
                }]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_psb_entries": [{
                    "index": 0,
                    "register_key": "phy_user_test_pattern_0",
                    "expected_descriptor": "0x01000083",
                    "expected_value": "0x00000000",
                    "value": "0x00000100"
                }]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_psb_serdes_entries": [
                    {
                        "index": 0,
                        "expected_address": "0x72001234",
                        "expected_value": 1,
                        "value": 0
                    },
                    {
                        "index": 0,
                        "expected_address": "0x72001234",
                        "expected_value": 1,
                        "value": 0
                    }
                ]
            }"#,
        )
        .is_err());
    }

    #[test]
    fn generates_identity_bound_expert_entry_configs() {
        let image = image_with_entry_blocks();
        let psb = image.expert_psb_entry_config(0, 0x0604_2018).unwrap();
        assert_eq!(psb.expert_psb_entries.len(), 1);
        assert_eq!(
            psb.expert_psb_entries[0].register_key,
            "phy_user_test_pattern_0"
        );
        assert_eq!(psb.expert_psb_entries[0].expected_descriptor, 0x1b00_0083);
        assert_eq!(psb.expert_psb_entries[0].expected_value, 0x0604_2019);
        assert!(image.expert_psb_entry_config(0, 0x0604_2019).is_err());
        assert!(image.expert_psb_entry_config(0, 0x06fb_2019).is_err());
        assert!(image.expert_psb_entry_config(2, 0).is_err());

        let serdes = image.expert_psb_serdes_entry_config(0, 0x1e).unwrap();
        assert_eq!(serdes.expert_psb_serdes_entries.len(), 1);
        assert_eq!(
            serdes.expert_psb_serdes_entries[0].expected_address,
            0x7200_1234
        );
        assert_eq!(serdes.expert_psb_serdes_entries[0].expected_value, 0x1f);
        assert!(image.expert_psb_serdes_entry_config(0, 0x1f).is_err());
        assert!(image.expert_psb_serdes_entry_config(2, 0).is_err());
    }

    #[test]
    fn rejects_unpaired_psb_records() {
        let mut bytes = vec![0u8; SOC_END + 8];
        bytes[..4].copy_from_slice(&ATLAS_SIGNATURE_PEX88096.to_le_bytes());
        bytes[SBR_INDEX_OFFSET..SBR_INDEX_OFFSET + 4]
            .copy_from_slice(&(SOC_END as u32).to_le_bytes());
        bytes[SBR_INDEX_OFFSET + 4..SBR_INDEX_OFFSET + 8].copy_from_slice(&4u32.to_le_bytes());
        let checksum = expected_checksum(&bytes[..SOC_END + 4]);
        bytes[SOC_END + 4..SOC_END + 8].copy_from_slice(&u32::from(checksum).to_le_bytes());

        let error = SbrImage::parse(bytes).unwrap_err().to_string();
        assert!(error.contains("psb contains value/address pairs"));
    }

    #[test]
    fn rejects_indexed_blocks_overlapping_soc_or_each_other() {
        let mut soc_overlap = minimal_image([[0; 4]; 6]).into_bytes();
        soc_overlap[SBR_INDEX_OFFSET + 2 * 4..SBR_INDEX_OFFSET + 3 * 4]
            .copy_from_slice(&(SOC_OFFSET as u32).to_le_bytes());
        soc_overlap[SBR_INDEX_OFFSET + 3 * 4..SBR_INDEX_OFFSET + 4 * 4]
            .copy_from_slice(&16u32.to_le_bytes());
        let checksum = expected_checksum(&soc_overlap[..SOC_END]);
        soc_overlap[SOC_END..SOC_END + 4].copy_from_slice(&u32::from(checksum).to_le_bytes());
        let error = SbrImage::parse(soc_overlap).unwrap_err().to_string();
        assert!(error.contains("psw0 starts"));
        assert!(error.contains("overlapping the fixed header"));

        let image = image_with_entry_blocks();
        let checksum_offset = image.checksum_offset();
        let mut block_overlap = image.into_bytes();
        block_overlap[SBR_INDEX_OFFSET + 18 * 4..SBR_INDEX_OFFSET + 19 * 4]
            .copy_from_slice(&((SOC_END + 8) as u32).to_le_bytes());
        block_overlap[SBR_INDEX_OFFSET + 19 * 4..SBR_INDEX_OFFSET + 20 * 4]
            .copy_from_slice(&24u32.to_le_bytes());
        let checksum = expected_checksum(&block_overlap[..checksum_offset]);
        block_overlap[checksum_offset..checksum_offset + 4]
            .copy_from_slice(&u32::from(checksum).to_le_bytes());
        let error = SbrImage::parse(block_overlap).unwrap_err().to_string();
        assert!(error.contains("psb-serdes"));
        assert!(error.contains("overlaps psb"));
    }

    #[test]
    fn rejects_enabled_vendor_reserved_index_pairs() {
        for (name, offset_index, size_index) in [("rsvd0", 14, 15), ("rsvd1", 20, 21)] {
            let mut bytes = minimal_image([[0; 4]; 6]).into_bytes();
            bytes[SBR_INDEX_OFFSET + offset_index * 4..SBR_INDEX_OFFSET + (offset_index + 1) * 4]
                .copy_from_slice(&(SOC_END as u32).to_le_bytes());
            bytes[SBR_INDEX_OFFSET + size_index * 4..SBR_INDEX_OFFSET + (size_index + 1) * 4]
                .copy_from_slice(&4u32.to_le_bytes());
            let error = SbrImage::parse(bytes).unwrap_err().to_string();
            assert!(error.contains(name));
            assert!(error.contains("index pair is reserved"));
        }
    }

    #[test]
    fn station_mutation_changes_only_soc_and_checksum() {
        let mut image = minimal_image([[0; 4]; 6]);
        let before = image.bytes().to_vec();
        image
            .set_station_layout(4, StationLayout::X4X4X4X4)
            .unwrap();
        image.validate().unwrap();
        assert_eq!(image.station_codes(4).unwrap(), [1, 1, 1, 1]);
        assert_eq!(image.station_codes(3).unwrap(), [0, 0, 0, 0]);

        let differences = byte_differences(&before, image.bytes());
        assert!(differences
            .iter()
            .all(|difference| matches!(difference.offset, 0x64 | 0x65)
                || difference.offset == SOC_END));
    }

    #[test]
    fn declarative_config_changes_only_named_fields_and_checksum() {
        let mut image = minimal_image([[0; 4]; 6]);
        let before = image.bytes().to_vec();
        let config = AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "soc": {
                    "upstream_port": 42,
                    "max_link_speed": "gen4"
                },
                "stations": [
                    {"station": 4, "layout": "x4x4x4x4"}
                ]
            }"#,
        )
        .unwrap();

        image.apply_config(&config).unwrap();
        assert_eq!(image.upstream_port(), 42);
        assert_eq!(image.max_link_speed(), PcieGeneration::Gen4);
        assert_eq!(image.station_codes(4).unwrap(), [1, 1, 1, 1]);
        assert_eq!(image.station_codes(5).unwrap(), [0, 0, 0, 0]);
        image.validate().unwrap();

        let differences = byte_differences(&before, image.bytes());
        assert!(differences.iter().all(|difference| {
            matches!(difference.offset, 0x5c | 0x5d | 0x64 | 0x65) || difference.offset == SOC_END
        }));
    }

    #[test]
    fn config_parser_rejects_unknown_duplicate_and_empty_inputs() {
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "soc": {"upstream_port": 96}
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "soc": {"upstream_port": 200}
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "soc": {"upstream_port": 116}
            }"#,
        )
        .is_ok());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "mystery": 1,
                "stations": [{"station": 4, "layout": "x16"}]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "stations": [
                    {"station": 4, "layout": "x16"},
                    {"station": 4, "layout": "x4x4x4x4"}
                ]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(br#"{"schema": "pexctl.atlas-config.v1"}"#,).is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_soc_fields": [
                    {"field": "soc.not_a_field", "expected": 0, "value": 1}
                ]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_soc_fields": [
                    {"field": "soc.upstream_port", "expected": 0, "value": 1}
                ]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_soc_fields": [
                    {"field": "soc.fanout_enable", "expected": 0, "value": 2}
                ]
            }"#,
        )
        .is_err());
        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_soc_fields": [
                    {"field": "soc.fanout_enable", "expected": 0, "value": 1},
                    {"field": "soc.fanout_enable", "expected": 0, "value": 1}
                ]
            }"#,
        )
        .is_err());
    }

    #[test]
    fn expert_fields_require_opt_in_and_expected_current_match() {
        let original = minimal_image([[0; 4]; 6]);
        let config = AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_soc_fields": [
                    {"field": "soc.fanout_enable", "expected": 0, "value": 1}
                ]
            }"#,
        )
        .unwrap();

        let mut without_opt_in = original.clone();
        assert!(without_opt_in.apply_config(&config).is_err());
        assert_eq!(without_opt_in, original);

        let mut candidate = original.clone();
        candidate.apply_config_with_policy(&config, true).unwrap();
        assert_eq!(candidate.read_bits(0x68 * 8 + 20, 1), 1);
        candidate.validate().unwrap();
        let differences = byte_differences(original.bytes(), candidate.bytes());
        assert!(differences
            .iter()
            .all(|difference| difference.offset == 0x6a || difference.offset == SOC_END));
        assert!(original
            .diff(&candidate)
            .named_differences
            .iter()
            .any(|difference| difference.field == "soc.fanout_enable"));

        let mismatch = AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_soc_fields": [
                    {"field": "soc.fanout_enable", "expected": 1, "value": 0}
                ]
            }"#,
        )
        .unwrap();
        let mut unchanged = original.clone();
        assert!(unchanged.apply_config_with_policy(&mismatch, true).is_err());
        assert_eq!(unchanged, original);
    }

    #[test]
    fn exposes_extended_soc_catalog_without_changing_v1_plan_inspections() {
        let original = minimal_image([[0; 4]; 6]);
        let legacy_inspection = original.inspection();
        assert_eq!(
            legacy_inspection.soc.named_fields.len(),
            ATLAS_INSPECTION_V1_SOC_FIELD_COUNT
        );
        assert!(!legacy_inspection
            .soc
            .named_fields
            .iter()
            .any(|field| field.name == "soc.customer_scratch1"));

        let field_inspection = original.soc_field_inspection();
        assert_eq!(field_inspection.schema, ATLAS_SOC_FIELD_INSPECTION_SCHEMA);
        assert_eq!(
            field_inspection.fields.len(),
            ATLAS_INSPECTION_V1_SOC_FIELD_COUNT + 19
        );
        assert!(field_inspection.fields.iter().any(|field| field.name
            == "soc.ethernet_tx_clock_divider"
            && field.offset == 0x6c
            && field.bit_low == 6
            && field.bit_high == 7));
        assert!(field_inspection
            .fields
            .iter()
            .any(|field| field.name == "soc.customer_scratch1"
                && field.offset == 0x74
                && field.bit_low == 0
                && field.bit_high == 7));
        assert!(field_inspection.fields.iter().any(|field| field.name
            == "soc.pvtmon_pulse_count_high"
            && field.offset == 0x140
            && field.bit_low == 8
            && field.bit_high == 10));
        assert!(field_inspection
            .fields
            .iter()
            .any(|field| field.name == "soc.pvtmon_ring_select"
                && field.offset == 0x140
                && field.bit_low == 12
                && field.bit_high == 15));

        let generated = original
            .expert_soc_field_config("soc.ethernet_tx_clock_divider", 3)
            .unwrap();
        assert_eq!(generated.expert_soc_fields.len(), 1);
        assert_eq!(
            generated.expert_soc_fields[0],
            ExpertSocFieldPatch {
                field: "soc.ethernet_tx_clock_divider".into(),
                expected: 0,
                value: 3,
            }
        );
        assert!(original
            .expert_soc_field_config("soc.ethernet_tx_clock_divider", 4)
            .is_err());
        assert!(original
            .expert_soc_field_config("soc.customer_scratch1", 0)
            .is_err());
        assert!(original
            .expert_soc_field_config("soc.upstream_port", 1)
            .is_err());
        assert!(original
            .expert_soc_field_config("soc.not_a_field", 1)
            .is_err());
        assert!(original
            .expert_soc_field_config("soc.pvtmon_pulse_count_high", 8)
            .is_err());
        assert!(original
            .expert_soc_field_config("soc.pvtmon_ring_select", 15)
            .is_ok());

        let config = AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_soc_fields": [
                    {
                        "field": "soc.ethernet_tx_clock_divider",
                        "expected": 0,
                        "value": 3
                    },
                    {
                        "field": "soc.customer_scratch1",
                        "expected": 0,
                        "value": 165
                    },
                    {
                        "field": "soc.dcsg_configuration",
                        "expected": 0,
                        "value": 90
                    }
                ]
            }"#,
        )
        .unwrap();
        let mut candidate = original.clone();
        candidate.apply_config_with_policy(&config, true).unwrap();
        candidate.validate().unwrap();

        let fields = candidate.soc_field_inspection();
        assert_eq!(
            fields
                .fields
                .iter()
                .find(|field| field.name == "soc.ethernet_tx_clock_divider")
                .unwrap()
                .value,
            3
        );
        assert_eq!(
            fields
                .fields
                .iter()
                .find(|field| field.name == "soc.customer_scratch1")
                .unwrap()
                .value,
            0xa5
        );
        assert_eq!(
            fields
                .fields
                .iter()
                .find(|field| field.name == "soc.dcsg_configuration")
                .unwrap()
                .value,
            0x5a
        );
        assert!(byte_differences(original.bytes(), candidate.bytes())
            .iter()
            .all(|difference| matches!(difference.offset, 0x6c | 0x74 | 0x76 | SOC_END)));
        assert!(original.diff(&candidate).named_differences.is_empty());

        assert!(AtlasConfig::parse_json(
            br#"{
                "schema": "pexctl.atlas-config.v1",
                "expert_soc_fields": [
                    {
                        "field": "soc.ethernet_tx_clock_divider",
                        "expected": 0,
                        "value": 4
                    }
                ]
            }"#,
        )
        .is_err());
    }

    #[test]
    fn decodes_database_defined_port_type_and_clock_mode_tables() {
        let mut image = minimal_image([[0; 4]; 6]);
        let values = [(0, 1, 2), (15, 2, 3), (16, 3, 1), (95, 1, 3)];
        for (port, port_type, clock_mode) in values {
            let location = port_default_location(port).unwrap();
            image.write_bits(
                location.port_type_offset * 8 + usize::from(location.port_type_bit_low),
                2,
                port_type,
            );
            image.write_bits(
                location.clock_mode_offset * 8 + usize::from(location.clock_mode_bit_low),
                2,
                clock_mode,
            );
        }
        for (port, port_type, clock_mode) in [(116, 2, 1), (117, 3, 2)] {
            let location = port_default_location(port).unwrap();
            image.write_bits(
                location.port_type_offset * 8 + usize::from(location.port_type_bit_low),
                2,
                port_type,
            );
            image.write_bits(
                location.clock_mode_offset * 8 + usize::from(location.clock_mode_bit_low),
                2,
                clock_mode,
            );
        }
        image.update_checksum();
        image.validate().unwrap();

        let inspection = image.port_defaults_inspection();
        assert_eq!(inspection.schema, ATLAS_PORT_DEFAULT_INSPECTION_SCHEMA);
        assert_eq!(inspection.ports.len(), 98);
        assert!(!inspection.ports.iter().any(|entry| entry.port == 96));

        let port0 = &inspection.ports[0];
        assert_eq!(port0.port_type_raw, 1);
        assert_eq!(port0.port_type_offset, 0xc0);
        assert_eq!(port0.port_type_bit_low, 0);
        assert_eq!(port0.clock_mode_raw, 2);
        assert_eq!(port0.clock_mode_offset, 0xe0);
        assert_eq!(port0.clock_mode_bit_low, 0);

        let port95 = inspection
            .ports
            .iter()
            .find(|entry| entry.port == 95)
            .unwrap();
        assert_eq!(port95.port_type_raw, 1);
        assert_eq!(port95.port_type_offset, 0xd4);
        assert_eq!(port95.port_type_bit_low, 30);
        assert_eq!(port95.clock_mode_raw, 3);
        assert_eq!(port95.clock_mode_offset, 0xf4);
        assert_eq!(port95.clock_mode_bit_low, 30);

        let port116 = inspection
            .ports
            .iter()
            .find(|entry| entry.port == 116)
            .unwrap();
        assert_eq!(port116.port_type_raw, 2);
        assert_eq!(port116.port_type_offset, 0xdc);
        assert_eq!(port116.port_type_bit_low, 8);
        assert_eq!(port116.clock_mode_raw, 1);
        assert_eq!(port116.clock_mode_offset, 0xf8);
        assert_eq!(port116.clock_mode_bit_low, 24);

        let port117 = inspection.ports.last().unwrap();
        assert_eq!(port117.port, 117);
        assert_eq!(port117.port_type_raw, 3);
        assert_eq!(port117.port_type_bit_low, 10);
        assert_eq!(port117.clock_mode_raw, 2);
        assert_eq!(port117.clock_mode_bit_low, 26);
        assert!(inspection
            .ports
            .iter()
            .all(|entry| entry.write_policy == "read-only"));
    }

    #[test]
    fn inspection_and_editable_config_preserve_unclassified_stations() {
        let image = minimal_image([
            [0, 0, 0, 0],
            [1, 1, 1, 1],
            [7, 7, 7, 7],
            [1, 1, 7, 7],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ]);
        let inspection = image.inspection();
        assert_eq!(inspection.soc.raw_dwords.len(), SOC_SIZE / 4);
        assert!(inspection
            .soc
            .named_fields
            .iter()
            .any(|field| field.name == "soc.auto_pcie_link_train_enable"));
        assert!(inspection
            .soc
            .named_fields
            .iter()
            .any(|field| field.name == "soc.secure_boot_enable"));
        assert_eq!(
            inspection
                .soc
                .named_fields
                .iter()
                .filter(|field| field.write_policy == "ordinary")
                .count(),
            2
        );
        assert_eq!(inspection.stations[0].layout, Some(StationLayout::X16));
        assert_eq!(inspection.stations[1].layout, Some(StationLayout::X4X4X4X4));
        assert_eq!(inspection.stations[2].layout, None);
        assert_eq!(inspection.stations[3].codes, [1, 1, 7, 7]);

        let config = image.editable_config();
        assert_eq!(config.stations[2].layout, None);
        assert_eq!(config.stations[3].layout, None);
        let round_trip = AtlasConfig::parse_json(&config.to_json_pretty().unwrap()).unwrap();
        assert_eq!(round_trip, config);
    }

    #[test]
    fn diff_names_understood_changes() {
        let before = minimal_image([[0; 4]; 6]);
        let mut after = before.clone();
        let config = AtlasConfig {
            schema: ATLAS_CONFIG_SCHEMA.into(),
            soc: AtlasSocConfig {
                upstream_port: Some(3),
                max_link_speed: Some(PcieGeneration::Gen4),
            },
            stations: vec![AtlasStationConfig {
                station: 4,
                layout: Some(StationLayout::X4X4X4X4),
            }],
            expert_soc_fields: Vec::new(),
            expert_psb_entries: Vec::new(),
            expert_psb_serdes_entries: Vec::new(),
        };
        after.apply_config(&config).unwrap();
        let report = before.diff(&after);
        assert!(report
            .named_differences
            .iter()
            .any(|difference| difference.field == "soc.upstream_port"));
        assert!(report
            .named_differences
            .iter()
            .any(|difference| difference.field == "soc.max_link_speed"));
        assert_eq!(report.station_differences.len(), 1);
        assert_eq!(report.station_differences[0].station, 4);
    }

    #[test]
    fn detects_truncation_from_index() {
        let mut image = minimal_image([[0; 4]; 6]).into_bytes();
        image[SBR_INDEX_OFFSET..SBR_INDEX_OFFSET + 4].copy_from_slice(&0x1fcu32.to_le_bytes());
        image[SBR_INDEX_OFFSET + 4..SBR_INDEX_OFFSET + 8].copy_from_slice(&0x48u32.to_le_bytes());
        assert!(SbrImage::parse(image).is_err());
    }

    #[test]
    fn normalizes_bdfs() {
        assert_eq!(normalize_bdf("c4:00.0").unwrap(), "0000:c4:00.0");
        assert_eq!(normalize_bdf("0000:C4:00.0").unwrap(), "0000:c4:00.0");
        assert!(normalize_bdf("c4:0.0").is_err());
    }

    #[test]
    fn decodes_spi_flash_programming_preflight() {
        let identity = [0xef, 0x60, 0x18];
        let clean = SpiFlashStatus::from_registers("0000:c4:00.0", identity, 0, 0, 0, None);
        assert_eq!(clean.schema, SPI_FLASH_STATUS_SCHEMA);
        assert!(clean.programming_preflight_passed);
        assert!(clean.require_programming_preflight().is_ok());

        let global_protection = SpiFlashStatus::from_registers(
            "0000:c4:00.0",
            identity,
            SPI_STATUS_1_BLOCK_PROTECT_MASK | SPI_STATUS_1_TOP_BOTTOM,
            SPI_STATUS_2_COMPLEMENT_PROTECT,
            0,
            None,
        );
        assert_eq!(global_protection.block_protect, 7);
        assert!(global_protection.top_bottom);
        assert!(global_protection.complement_protect);
        assert!(!global_protection.programming_preflight_passed);
        assert!(global_protection
            .require_programming_preflight()
            .unwrap_err()
            .to_string()
            .contains("BP/CMP"));

        let individual_locked = SpiFlashStatus::from_registers(
            "0000:c4:00.0",
            identity,
            0,
            0,
            SPI_STATUS_3_WRITE_PROTECT_SELECTION,
            Some(SPI_BLOCK_LOCKED),
        );
        assert_eq!(individual_locked.sector0_individual_lock, Some(true));
        assert!(!individual_locked.programming_preflight_passed);

        let individual_unlocked = SpiFlashStatus::from_registers(
            "0000:c4:00.0",
            identity,
            SPI_STATUS_1_BLOCK_PROTECT_MASK,
            SPI_STATUS_2_COMPLEMENT_PROTECT,
            SPI_STATUS_3_WRITE_PROTECT_SELECTION,
            Some(0),
        );
        assert_eq!(individual_unlocked.sector0_individual_lock, Some(false));
        assert!(individual_unlocked.programming_preflight_passed);
    }

    #[test]
    fn spi_flash_preflight_rejects_active_or_suspended_operations() {
        let status = SpiFlashStatus::from_registers(
            "0000:c4:00.0",
            [0xef, 0x60, 0x18],
            SPI_STATUS_1_BUSY | SPI_STATUS_1_WRITE_ENABLE_LATCH,
            SPI_STATUS_2_ERASE_PROGRAM_SUSPENDED,
            0,
            None,
        );
        assert!(!status.programming_preflight_passed);
        assert_eq!(status.refusal_reasons.len(), 3);
        assert!(status
            .refusal_reasons
            .iter()
            .any(|reason| reason.contains("BUSY")));
        assert!(status
            .refusal_reasons
            .iter()
            .any(|reason| reason.contains("WEL")));
        assert!(status
            .refusal_reasons
            .iter()
            .any(|reason| reason.contains("suspended")));
    }

    #[test]
    fn sector_replacement_rejects_changes_outside_sbr() {
        let sbr = minimal_image([[0; 4]; 6]);
        let mut current = vec![0xff; ATLAS_SPI_RECOVERY_REGION_SIZE];
        let start = SBR_FLASH_OFFSET as usize;
        current[start..start + sbr.bytes().len()].copy_from_slice(sbr.bytes());

        let mut valid_candidate = current.clone();
        let mut changed_sbr = sbr.clone();
        changed_sbr
            .set_station_layout(4, StationLayout::X4X4X4X4)
            .unwrap();
        valid_candidate[start..start + changed_sbr.bytes().len()]
            .copy_from_slice(changed_sbr.bytes());
        validate_sector0_replacement(&current, &valid_candidate).unwrap();

        valid_candidate[0] = 0;
        assert!(validate_sector0_replacement(&current, &valid_candidate).is_err());
    }

    #[test]
    fn sector_replacement_rejects_sbr_changes_beyond_programmed_erase_block() {
        fn large_sbr(value: u32) -> SbrImage {
            let block_offset = 0x1_0000usize;
            let checksum_offset = block_offset + 8;
            let mut bytes = vec![0u8; checksum_offset + 4];
            bytes[..4].copy_from_slice(&ATLAS_SIGNATURE_PEX88096.to_le_bytes());
            bytes[SBR_INDEX_OFFSET + 18 * 4..SBR_INDEX_OFFSET + 19 * 4]
                .copy_from_slice(&(block_offset as u32).to_le_bytes());
            bytes[SBR_INDEX_OFFSET + 19 * 4..SBR_INDEX_OFFSET + 20 * 4]
                .copy_from_slice(&8u32.to_le_bytes());
            bytes[block_offset..block_offset + 4].copy_from_slice(&0x6041_0064u32.to_le_bytes());
            bytes[block_offset + 4..block_offset + 8].copy_from_slice(&value.to_le_bytes());
            let checksum = expected_checksum(&bytes[..checksum_offset]);
            bytes[checksum_offset..checksum_offset + 4]
                .copy_from_slice(&u32::from(checksum).to_le_bytes());
            SbrImage::parse(bytes).unwrap()
        }

        let current_sbr = large_sbr(0x1f);
        let candidate_sbr = large_sbr(0x1e);
        let mut current = vec![0xff; ATLAS_SPI_RECOVERY_REGION_SIZE];
        let mut candidate = current.clone();
        let start = SBR_FLASH_OFFSET as usize;
        current[start..start + current_sbr.bytes().len()].copy_from_slice(current_sbr.bytes());
        candidate[start..start + candidate_sbr.bytes().len()]
            .copy_from_slice(candidate_sbr.bytes());

        let error = validate_sector0_replacement(&current, &candidate)
            .unwrap_err()
            .to_string();
        assert!(error.contains("beyond the one 0x10000-byte block"));
    }

    #[test]
    fn plx_ioctl_numbers_match_sdk_8_23_abi() {
        assert_eq!(std::mem::size_of::<PlxParams>(), 356);
        assert_eq!(PLX_IOCTL_DRIVER_VERSION, 0xc164_5000);
        assert_eq!(PLX_IOCTL_PCI_DEVICE_FIND, 0xc164_5007);
        assert_eq!(PLX_IOCTL_MAPPED_REGISTER_READ, 0xc164_5011);
        assert_eq!(PLX_IOCTL_MAPPED_REGISTER_WRITE, 0xc164_5012);
    }

    #[test]
    fn sha256_matches_standard_vector() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
