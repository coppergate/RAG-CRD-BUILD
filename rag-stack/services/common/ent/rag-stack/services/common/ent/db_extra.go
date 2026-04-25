package ent

import (
	"database/sql"
	entSql "entgo.io/ent/dialect/sql"
)

// DB returns the underlying sql.DB.
func (c *Client) DB() *sql.DB {
	if driver, ok := c.driver.(*entSql.Driver); ok {
		return driver.DB()
	}
	return nil
}
