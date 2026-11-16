FROM osrm/osrm-backend:latest
WORKDIR /data
RUN apt-get update && apt-get install -y curl ca-certificates && \
    curl -L -o zambia-latest.osm.pbf https://download.geofabrik.de/africa/zambia-latest.osm.pbf
RUN osrm-extract -p /opt/car.lua zambia-latest.osm.pbf && \
    osrm-partition zambia-latest.osrm && \
    osrm-customize zambia-latest.osrm
EXPOSE 5000
CMD ["osrm-routed", "--algorithm", "mld", "-p", "5000", "zambia-latest.osrm"]
