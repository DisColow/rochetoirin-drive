import json,os,sys,urllib.request
UA={'User-Agent':'Mozilla/5.0 rochetoirin-drive'}
def get(u): return urllib.request.urlopen(urllib.request.Request(u,headers=UA)).read()
for m in sys.argv[1:]:
    d=json.loads(get("https://api.polyhaven.com/files/"+m))
    g=d['gltf']['1k']['gltf']
    os.makedirs(m,exist_ok=True)
    open(os.path.join(m,m+'.gltf'),'wb').write(get(g['url']))
    for p,v in g['include'].items():
        os.makedirs(os.path.join(m,os.path.dirname(p)),exist_ok=True)
        open(os.path.join(m,p),'wb').write(get(v['url']))
    # cartes d'opacité (feuilles détourées) : fournies à part par Poly Haven
    alpha = {}
    if 'Alpha' in d:
        u = d['Alpha']['1k']['png']['url']; f = 'textures/' + u.split('/')[-1]
        open(os.path.join(m, f), 'wb').write(get(u)); alpha['*'] = f
    for k, v in d.items():
        if k.endswith('_alpha') and '1k' in v:
            u = v['1k']['png']['url']; f = 'textures/' + u.split('/')[-1]
            open(os.path.join(m, f), 'wb').write(get(u)); alpha[k[:-6]] = f
    json.dump(alpha, open(os.path.join(m, 'alpha.json'), 'w'))
    print(m, 'ok', alpha)
