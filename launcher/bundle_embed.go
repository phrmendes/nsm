//go:build bundle

package main

import _ "embed"

//go:embed bundle.tar.gz
var bundle []byte
