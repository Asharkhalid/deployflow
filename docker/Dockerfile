# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy csproj and restore as distinct layers
COPY ["src/SampleApi/SampleApi.csproj", "SampleApi/"]
RUN dotnet restore "SampleApi/SampleApi.csproj"

# Copy everything else and build
COPY src/ .
WORKDIR "/src/SampleApi"
RUN dotnet build "SampleApi.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "SampleApi.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Final production stage using Alpine for smaller footprint and better security
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Run as non-root user for security (app user is created in Alpine .NET images)
USER $APP_UID

# Expose standard port for the application
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

ENTRYPOINT ["dotnet", "SampleApi.dll"]
