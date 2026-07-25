//! Lossless helpers for Broadcom/PLX Atlas SBR images and live devices.
//!
//! The format support here is deliberately conservative. Unknown bytes are
//! retained verbatim, and mutation APIs expose only fields that have been
//! confirmed against both a live PEX88096 image and Broadcom's RDK96 image.

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use sha2::{Digest, Sha256};
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
pub const ATLAS_INSPECTION_SCHEMA: &str = "pexctl.atlas-sbr-inspection.v1";
pub const ATLAS_DIFF_SCHEMA: &str = "pexctl.atlas-sbr-diff.v1";
pub const ATLAS_ENTRY_INSPECTION_SCHEMA: &str = "pexctl.atlas-entry-inspection.v1";
const PSB_MAX_SIZE: u32 = 0x2000;
const PSB_SERDES_MAX_SIZE: u32 = 0x4000;
const PSB_REGISTER_WORD_MASK: u32 = 0x000f_ffff;
const PSB_BYTE_MASK_MASK: u32 = 0x0f00_0000;
const PSB_BROADCAST_MASK: u32 = 0x1000_0000;
const AXI_BROADCAST_ADDRESS_MASK: u32 = 0x7000_0000;
const AXI_BROADCAST_ADDRESS_VALUE: u32 = 0x7000_0000;
const AXI_BROADCAST_MODE_MASK: u32 = 0x0300_0000;
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

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct AtlasApplyPolicy {
    pub allow_expert_soc_fields: bool,
    pub allow_expert_entries: bool,
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
];

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
                named_fields: NAMED_SOC_FIELDS
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
                    .collect(),
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
        let named_differences = NAMED_SOC_FIELDS
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
        for block in self.blocks() {
            if block.state() == BlockState::Invalid {
                return Err(Error::Format(format!(
                    "{} has nonzero offset {:#x} and zero size",
                    block.kind.name(),
                    block.offset
                )));
            }
            if let Some(end) = block.end() {
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
const SPI_CMD_READ_STATUS: u8 = 0x05;
const SPI_CMD_WRITE_ENABLE: u8 = 0x06;
const SPI_CMD_WRITE_PAGE: u8 = 0x02;
const SPI_STATUS_WRITE_IN_PROGRESS: u8 = 1 << 0;
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
        let required_confirmation = format!(
            "ERASE-PROGRAM-VERIFY:{}:CS0:SECTOR0",
            self.bdf.to_ascii_lowercase()
        );
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

        self.spi_write_enable(true)?;
        self.spi_command(0, &[SPI_CMD_ERASE_SECTOR, 0, 0, 0], 0)?;
        self.spi_wait_flash_ready(Duration::from_secs(180))?;

        for (page_index, page) in candidate[..ATLAS_SPI_ERASE_BLOCK_SIZE]
            .chunks_exact(SPI_PAGE_SIZE)
            .enumerate()
        {
            if page.iter().all(|byte| *byte == 0xff) {
                continue;
            }
            let address = page_index * SPI_PAGE_SIZE;
            self.spi_write_enable(true)?;
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
            self.spi_wait_flash_ready(Duration::from_secs(5))?;
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

    fn spi_write_enable(&self, more_commands: bool) -> Result<()> {
        self.spi_command(
            if more_commands { SPI_MORE_COMMANDS } else { 0 },
            &[SPI_CMD_WRITE_ENABLE],
            0,
        )
        .map(|_| ())
    }

    fn spi_wait_flash_ready(&self, timeout: Duration) -> Result<()> {
        let started = Instant::now();
        loop {
            let status = self.spi_command(0, &[SPI_CMD_READ_STATUS], 1)?[0];
            if status & SPI_STATUS_WRITE_IN_PROGRESS == 0 {
                return Ok(());
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

fn normalize_bdf(value: &str) -> Result<String> {
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
