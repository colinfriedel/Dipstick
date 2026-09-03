package models

import (
	"database/sql/driver"
	"fmt"
	"strings"
	"time"
)

// dateLayout is Go's reference time formatted as an ISO calendar date.
const dateLayout = "2006-01-02"

// Date is a calendar date with no time-of-day and no timezone — exactly what the
// Postgres DATE column stores. Using this instead of time.Time keeps a value
// that is conceptually "2024-03-14" from carrying a midnight timestamp and a
// timezone that can silently shift it across a day boundary.
//
// It implements the four interfaces Go needs to carry a value across both
// boundaries the service cares about:
//
//	JSON  <-> Go : json.Marshaler / json.Unmarshaler
//	Go    <-> DB : driver.Valuer  / sql.Scanner
type Date struct {
	Year  int
	Month time.Month
	Day   int
}

// DateOf collapses a time.Time to its calendar date.
func DateOf(t time.Time) Date {
	return Date{Year: t.Year(), Month: t.Month(), Day: t.Day()}
}

// ParseDate reads a "YYYY-MM-DD" string.
func ParseDate(s string) (Date, error) {
	t, err := time.Parse(dateLayout, s)
	if err != nil {
		return Date{}, fmt.Errorf("date must be YYYY-MM-DD: %w", err)
	}
	return DateOf(t), nil
}

func (d Date) String() string {
	return fmt.Sprintf("%04d-%02d-%02d", d.Year, int(d.Month), d.Day)
}

// IsZero reports whether the Date is the zero value (no date set).
func (d Date) IsZero() bool {
	return d == Date{}
}

func (d Date) toTime() time.Time {
	return time.Date(d.Year, d.Month, d.Day, 0, 0, 0, 0, time.UTC)
}

// Before / Equal give a total ordering, used when sorting fuel entries.
func (d Date) Before(other Date) bool { return d.toTime().Before(other.toTime()) }
func (d Date) Equal(other Date) bool  { return d == other }

// DaysUntil returns the whole days from d to other: positive if other is later,
// negative if earlier. Both sides are UTC midnight, so the difference is an
// exact multiple of 24h and DST never enters into it.
func (d Date) DaysUntil(other Date) int {
	return int(other.toTime().Sub(d.toTime()).Hours()) / 24
}

// Today is the current calendar date in the server's local timezone (UTC in the
// container unless TZ is set). Good enough for due-date buffers measured in days.
func Today() Date {
	return DateOf(time.Now())
}

// MarshalJSON renders the date as a quoted "YYYY-MM-DD" string, or null when the
// Date is the zero value. Treating zero as null lets an optional date field
// (e.g. a maintenance entry's nextDueDate) be a plain Date rather than a *Date.
func (d Date) MarshalJSON() ([]byte, error) {
	if d.IsZero() {
		return []byte("null"), nil
	}
	return []byte(`"` + d.String() + `"`), nil
}

// UnmarshalJSON accepts a quoted "YYYY-MM-DD" string (or null / empty -> zero).
func (d *Date) UnmarshalJSON(data []byte) error {
	s := strings.Trim(string(data), `"`)
	if s == "" || s == "null" {
		*d = Date{}
		return nil
	}
	parsed, err := ParseDate(s)
	if err != nil {
		return err
	}
	*d = parsed
	return nil
}

// Value implements driver.Valuer: how a Date is handed to the DB driver. A zero
// Date becomes SQL NULL; otherwise we send a time.Time and pgx writes it to the
// DATE column.
func (d Date) Value() (driver.Value, error) {
	if d.IsZero() {
		return nil, nil
	}
	return d.toTime(), nil
}

// Scan implements sql.Scanner: how a Date is populated from a DB value. pgx
// returns DATE columns as time.Time, but we handle string/[]byte too for
// robustness against other drivers or explicit ::text casts.
func (d *Date) Scan(src any) error {
	switch v := src.(type) {
	case nil:
		*d = Date{}
		return nil
	case time.Time:
		*d = DateOf(v)
		return nil
	case string:
		parsed, err := ParseDate(v)
		if err != nil {
			return err
		}
		*d = parsed
		return nil
	case []byte:
		parsed, err := ParseDate(string(v))
		if err != nil {
			return err
		}
		*d = parsed
		return nil
	default:
		return fmt.Errorf("cannot scan %T into models.Date", src)
	}
}
