# ---- build stage ----
# Uses the full SDK image to restore, build, and publish the app.
# This image is large (~900 MB) but is discarded after the build — it never ships.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy the project file first and restore dependencies.
# Docker caches this layer separately, so 'dotnet restore' only re-runs
# when EtlJob.csproj changes — not on every source code change.
COPY src/EtlJob/EtlJob.csproj ./EtlJob/
RUN dotnet restore ./EtlJob/EtlJob.csproj

# Copy the rest of the source and publish a Release build.
COPY src/EtlJob/ ./EtlJob/
RUN dotnet publish ./EtlJob/EtlJob.csproj -c Release -o /app --no-restore

# ---- runtime stage ----
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS final
WORKDIR /app

COPY --from=build /app ./

# Download and install the pinned New Relic .NET agent .deb directly — no apt repo needed.
RUN apt-get update && apt-get install -y curl \
 && curl -sL "https://download.newrelic.com/dot_net_agent/previous_releases/10.52.0/newrelic-dotnet-agent_10.52.0_amd64.deb" \
    -o /tmp/newrelic-dotnet-agent.deb \
 && dpkg -i /tmp/newrelic-dotnet-agent.deb \
 && rm /tmp/newrelic-dotnet-agent.deb \
 && rm -rf /var/lib/apt/lists/*

# Wire up the CoreCLR profiler — GUID is fixed for all New Relic .NET Core agents.
# NEW_RELIC_LICENSE_KEY and NEW_RELIC_APP_NAME are injected at runtime, not baked in.
ENV CORECLR_ENABLE_PROFILING=1 \
    CORECLR_PROFILER={36032161-FFC0-4B61-B559-F6C5D41BAE5A} \
    CORECLR_PROFILER_PATH=/usr/local/newrelic-dotnet-agent/libNewRelicProfiler.so \
    CORECLR_NEWRELIC_HOME=/usr/local/newrelic-dotnet-agent \
    NEW_RELIC_APPLICATION_LOGGING_ENABLED=true \
    NEW_RELIC_APPLICATION_LOGGING_FORWARDING_ENABLED=true \
    NEW_RELIC_SEND_DATA_ON_EXIT=true \
    NEW_RELIC_SEND_DATA_ON_EXIT_THRESHOLD_MS=0

ENTRYPOINT ["dotnet", "EtlJob.dll"]
