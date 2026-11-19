# Build
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY FamiliaRodriguez.csproj ./
RUN dotnet restore
COPY . ./
RUN dotnet publish -c Release -o /app/publish --no-restore

# Runtime
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DisableHttpsRedirection=true
ENV PathBase=
EXPOSE 8080

# Writable data for SQLite + DataProtection keys + GEDCOM
RUN mkdir -p /app/Data/Gedcom /app/Data/keys \
    && chmod -R 777 /app/Data

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "FamiliaRodriguez.dll"]
