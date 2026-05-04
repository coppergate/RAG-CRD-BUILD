package main

import (
	"context"
	"fmt"
	"testing"

	"app-builds/common/ent/enttest"
	_ "github.com/mattn/go-sqlite3"
	"github.com/stretchr/testify/assert"
)

func TestIDMonotonicity(t *testing.T) {
	// Use a fresh in-memory database
	client := enttest.Open(t, "sqlite3", "file:monotonic?mode=memory&cache=shared&_fk=1")
	defer client.Close()

	ctx := context.Background()

	// 1. Create multiple sessions without specifying IDs (letting Ent/DB generate them)
	var ids []int64
	for i := 0; i < 5; i++ {
		s, err := client.Session.Create().
			SetName(fmt.Sprintf("Session-%d", i)).
			Save(ctx)
		assert.NoError(t, err)
		ids = append(ids, s.ID)
	}

	// 2. Verify they are increasing (monotonically)
	// This confirms that our switch to BIGINT PKs supports standard auto-increment behavior
	for i := 1; i < len(ids); i++ {
		assert.True(t, ids[i] > ids[i-1], "ID %d should be greater than %d", ids[i], ids[i-1])
	}
}
