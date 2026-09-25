require "json"

STDIN.binmode
STDOUT.write(JSON.generate(arguments: ARGV, stdin_hex: STDIN.read.unpack1("H*")))
