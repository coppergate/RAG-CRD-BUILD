package main

import (
	"fmt"
	"app-builds/common/ent/session"
)

func main() {
	fmt.Printf("FieldID: %q\n", session.FieldID)
	fmt.Printf("FieldUserID: %q\n", session.FieldUserID)
}
