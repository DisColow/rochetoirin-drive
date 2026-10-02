const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const http=require('http'),fs=require('fs'),path=require('path');
const root=__dirname;
const srv=http.createServer((q,r)=>{const f=path.join(root,decodeURIComponent(q.url.split('?')[0]));fs.readFile(f,(e,d)=>{if(e){r.statusCode=404;return r.end();}
 if(f.endsWith('.js'))r.setHeader('Content-Type','text/javascript'); r.end(d);});}).listen(8766);
(async()=>{
  const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
  const p=await b.newPage(); p.on('console',m=>console.log(m.text())); p.on('pageerror',e=>console.log('ERR',e.message));
  await p.goto('http://localhost:8766/bake.html'); await p.waitForFunction('window.ready===true');
  for(const name of process.argv.slice(2)){
    const t=Date.now();
    const o=await p.evaluate(n=>window.bake(n),name);
    const dir=name.replace(':','__');fs.mkdirSync(path.join(root,'out',dir),{recursive:true});
    o.views.forEach((v,k)=>{for(const pass of ['col','nrm','dep'])fs.writeFileSync(path.join(root,'out',dir,`${pass}${k}.png`),Buffer.from(v[pass].split(',')[1],'base64'));});
    delete o.views; fs.writeFileSync(path.join(root,'out',dir,'info.json'),JSON.stringify(o));
    console.log(name,'ok',(Date.now()-t)/1000,'s',JSON.stringify(o));
  }
  await b.close(); srv.close();
})();
