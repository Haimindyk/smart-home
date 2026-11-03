import argparse
import json
from .data import prepare
from .portion import train

p = argparse.ArgumentParser()
commands = p.add_subparsers(dest="command", required=True)
a = commands.add_parser("prepare")
a.add_argument("input")
a.add_argument("output")
a.add_argument("--split-salt", required=True)
a.add_argument("--allow-synthetic", action="store_true")
a = commands.add_parser("train-portion")
a.add_argument("dataset")
a.add_argument("output")
args = p.parse_args()
if args.command == "prepare":
    result = prepare(args.input, args.output, args.split_salt, args.allow_synthetic)
else:
    result = train(args.dataset, args.output)
print(json.dumps(result, ensure_ascii=False, indent=2))
