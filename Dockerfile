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
# No New Relic agent baked in — logs flow via CloudWatch → Lambda → New Relic Log API.
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS final
WORKDIR /app

COPY --from=build /app ./

ENTRYPOINT ["dotnet", "EtlJob.dll"]
