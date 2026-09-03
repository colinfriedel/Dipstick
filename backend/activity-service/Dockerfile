# Multi-stage build — identical approach to vehicle-service's Dockerfile.
# Stage 1 compiles a static binary with the full Go toolchain; stage 2 ships
# just that binary on a minimal base.

# ---- Stage 1: build ----
FROM golang:1.23 AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /out/activity-service .

# ---- Stage 2: runtime ----
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/activity-service /activity-service

EXPOSE 8080

ENTRYPOINT ["/activity-service"]
