FROM golang:1.26.8@sha256:eb36c1664dd974cde625f736e02c204383deebe03977365caaec5bf49f794348 AS build
ARG RUNNER_COMMIT=df6b843fb929bb04b933b09c6bf208774d42480b
WORKDIR /src
RUN git init && git remote add origin https://code.forgejo.org/forgejo/runner.git \
    && git fetch --depth=1 origin ${RUNNER_COMMIT} && git checkout FETCH_HEAD
RUN CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath \
    -ldflags='-s -w -X code.forgejo.org/forgejo/runner/v13/internal/pkg/ver.version=v13.2.0' \
    -o /out/forgejo-runner.exe .
FROM scratch
COPY --from=build /out/forgejo-runner.exe /forgejo-runner.exe
