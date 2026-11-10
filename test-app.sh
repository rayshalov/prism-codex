#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc -O -parse-as-library -emit-module -emit-library -static \
  -module-name PrismCore -emit-module-path .build/checks/PrismCore.swiftmodule \
  -o .build/checks/libPrismCore.a Sources/PrismCore/*.swift
swiftc -O -parse-as-library -I .build/checks -L .build/checks -lPrismCore \
  -o .build/checks/PrismChecks Tests/PrismCoreTests/*.swift
exec .build/checks/PrismChecks "$@"
