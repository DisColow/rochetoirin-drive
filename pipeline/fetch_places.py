"""Lieux publics nommés de la zone (OSM, Overpass) pour les activités : destinations du taxi, lieux de la chasse.
Seulement des lieux publics (gares, mairies, églises, écoles, hôpitaux, postes, stades, piscines, médiathèques,
musées, châteaux, parcs, places) : jamais de commerces ni de marques.
Sortie : data/osm_places.json (éléments avec centre)."""
import json, time, urllib.parse, urllib.request

BB = "45.53,5.19,45.67,5.53"
SEL = [
    'nwr["railway"~"^(station|halt)$"]["name"]',
    'nwr["amenity"~"^(townhall|school|college|university|hospital|clinic|post_office|library|police|fire_station|'
    'marketplace|cinema|theatre|place_of_worship|bus_station|community_centre|kindergarten|nursing_home)$"]["name"]',
    'nwr["leisure"~"^(stadium|sports_centre|swimming_pool|park|golf_course)$"]["name"]["access"!="private"]',
    'nwr["tourism"~"^(museum|attraction|viewpoint)$"]["name"]',
    'nwr["historic"~"^(castle|monument|ruins|memorial)$"]["name"]',
    'nwr["place"~"^(square|hamlet|village|neighbourhood|quarter|suburb)$"]["name"]',
]


def main():
    q = "[out:json][timeout:300];(" + "".join("%s(%s);" % (s, BB) for s in SEL) + ");out tags center;"
    b = b""
    for k in range(8):
        u = ("https://maps.mail.ru/osm/tools/overpass/api/interpreter", "https://overpass-api.de/api/interpreter")[k % 2]
        try:
            b = urllib.request.urlopen(urllib.request.Request(u, data=urllib.parse.urlencode(dict(data=q)).encode()),
                                       timeout=600).read()
            if b[:1] == b"{":
                break
        except Exception as e:
            print("nouvel essai", u, e); time.sleep(10 * (k + 1))
    open("data/osm_places.json", "wb").write(b)
    print(len(json.loads(b)["elements"]), "lieux")


if __name__ == "__main__":
    main()
