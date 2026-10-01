#!/bin/sh
# Télécharge les routes et les lieux OpenStreetMap autour de Rochetoirin.
set -e
cd "$(dirname "$0")"
mkdir -p data
API=${OVERPASS:-https://maps.mail.ru/osm/tools/overpass/api/interpreter}
BB="45.552,5.383,45.618,5.445"
curl -s -m 300 "$API" --data-urlencode "data=[out:json][timeout:120];(way[\"highway\"]($BB);)->.r;(.r;>;);out body;relation(85685);out geom;" -o data/osm.json
curl -s -m 300 "$API" --data-urlencode "data=[out:json][timeout:120];(node[\"place\"]($BB);nwr[\"amenity\"]($BB);nwr[\"shop\"]($BB);nwr[\"building\"=\"church\"]($BB);nwr[\"leisure\"~\"pitch|sports_centre|park\"]($BB);nwr[\"craft\"]($BB);nwr[\"office\"]($BB);nwr[\"landuse\"=\"farmyard\"]($BB););out center tags;" -o data/pois.json
ls -la data/osm.json data/pois.json
curl -s -m 300 "$API" --data-urlencode "data=[out:json][timeout:120];(way[\"railway\"~\"^(rail|light_rail)$\"]($BB);node[\"railway\"=\"level_crossing\"]($BB);node[\"highway\"=\"street_lamp\"]($BB);node[\"traffic_calming\"]($BB);node[\"traffic_sign\"]($BB););(._;>;);out body;" -o data/osm_street.json
