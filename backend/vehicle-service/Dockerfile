# Multi-stage build.
#
# Stage 1 ("build") has the full Go toolchain and compiles a single static
# binary. Stage 2 starts from a near-empty base and copies just that binary in.
# The image we actually ship contains no compiler, no shell, no package
# manager — smaller to push/pull and a much smaller attack surface.

# ---- Stage 1: build ----
FROM golang:1.23 AS build

WORKDIR /src

# Copy only the module files first and download deps. Docker caches this layer,
# so `go mod download` only re-runs when go.mod/go.sum actually change — not on
# every source edit.
COPY go.mod go.sum ./
RUN go mod download

# Now copy the rest of the source and build.
COPY . .

# CGO_ENABLED=0 makes a fully static binary (no libc dependency), which is what
# lets it run on the tiny base image in stage 2.
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/vehicle-service .

# ---- Stage 2: runtime ----
# distroless/static: glibc-free, no shell, runs as a non-root user by default.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/vehicle-service /vehicle-service

EXPOSE 8080

ENTRYPOINT ["/vehicle-service"]
