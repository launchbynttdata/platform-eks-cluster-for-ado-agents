# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.26.5

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS build
WORKDIR /src

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
ARG COMMIT=unknown

COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
    -trimpath \
    -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" \
    -o /out/ado-keda-proxy ./cmd/ado-keda-proxy

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/ado-keda-proxy /ado-keda-proxy
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/ado-keda-proxy"]
