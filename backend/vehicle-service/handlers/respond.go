// Package handlers is the HTTP layer: it turns HTTP requests into store/service
// calls and turns the results (or errors) back into HTTP responses. It owns
// status codes and JSON encoding; it does not contain SQL or business rules.
package handlers

import (
	"encoding/json"
	"log"
	"net/http"
)

// writeJSON sets the content type, writes the status line, and encodes body.
// Order matters: once WriteHeader is called the status is locked in, so we set
// headers first.
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if body == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(body); err != nil {
		// The status and (likely) some bytes are already sent, so we can't
		// change the response — just record that it happened.
		log.Printf("handlers: encoding response body: %v", err)
	}
}

// errorResponse is the single shape every error reply uses, so the client can
// always look for the same "error" key.
type errorResponse struct {
	Error string `json:"error"`
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, errorResponse{Error: message})
}
