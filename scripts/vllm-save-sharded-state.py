#!/usr/bin/env python3
"""Save a multi-node vLLM model as rank-local sharded-state checkpoints."""

import argparse
import shlex
import subprocess
from pathlib import Path

from vllm import EngineArgs, LLM
from vllm.model_executor.model_loader import ShardedStateLoader
from vllm.utils.argparse_utils import FlexibleArgumentParser


def parse_args() -> argparse.Namespace:
    parser = FlexibleArgumentParser()
    EngineArgs.add_cli_args(parser)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--file-pattern",
        default=ShardedStateLoader.DEFAULT_PATTERN,
        help="Rank/part filename pattern used by the sharded-state loader",
    )
    parser.add_argument(
        "--max-file-size",
        type=int,
        default=8 * 1024**3,
        help="Maximum output safetensors part size in bytes",
    )
    parser.add_argument(
        "--prune-staging-host",
        action="append",
        default=[],
        help="SSH host whose staging weight files may be deleted after load",
    )
    return parser.parse_args()


def prune_staging_weights(hosts: list[str], model_path: Path) -> None:
    quoted_path = shlex.quote(str(model_path))
    command = (
        f"find {quoted_path} -maxdepth 1 -type f "
        "-name '*.safetensors' -delete"
    )
    for host in hosts:
        subprocess.run(["ssh", host, command], check=True)


def main(args: argparse.Namespace) -> None:
    engine_args = EngineArgs.from_cli_args(args)
    model_path = Path(engine_args.model)
    if not model_path.is_dir():
        raise ValueError(f"model path is not a local directory: {model_path}")

    llm = LLM.from_engine_args(engine_args)

    # LLM construction does not return until every rank has loaded its weights.
    # Removing staging weights here bounds peak disk use on small worker disks.
    if args.prune_staging_host:
        prune_staging_weights(args.prune_staging_host, model_path)

    llm.llm_engine.engine_core.save_sharded_state(
        path=str(args.output),
        pattern=args.file_pattern,
        max_size=args.max_file_size,
    )


if __name__ == "__main__":
    main(parse_args())
