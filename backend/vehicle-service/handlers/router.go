package handlers

import (
	"log"
	"net/http"
	"time"
)

// NewRouter wires every route to its handler and returns the resulting
// http.Handler, wrapped in request logging.
//
// Go 1.22+ gave net/http's ServeMux method-aware, path-variable-aware routing.
// Patterns like "GET /vehicles/{id}" mean we no longer need a third-party router
// for basic REST. Inside a handler, r.PathValue("id") reads the {id} segment.
func NewRouter(s VehicleStore) http.Handler {
	mux := http.NewServeMux()
	h := &VehicleHandler{store: s}

	// Liveness probe — used by Docker Compose / deploy platforms to know the
	// process is up. It does not check the database on purpose: this answers
	// "is the server running", not "is everything healthy".
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("GET /vehicles", h.List)
	mux.HandleFunc("POST /vehicles", h.Create)
	mux.HandleFunc("GET /vehicles/{id}", h.Get)
	mux.HandleFunc("PUT /vehicles/{id}", h.Update)
	mux.HandleFunc("DELETE /vehicles/{id}", h.Delete)

	return requestLogger(mux)
}

// requestLogger is middleware: a handler that wraps another handler, does
// something before/after, and calls through. This pattern — func(http.Handler)
// http.Handler — is how cross-cutting concerns (logging, auth, metrics) compose
// in idiomatic net/http.
func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s (%s)", r.Method, r.URL.Path, time.Since(start))
	})
}
