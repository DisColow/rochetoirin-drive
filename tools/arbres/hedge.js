const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const http=require('http'),fs=require('fs'),path=require('path');
const root=__dirname;
const srv=http.createServer((q,r)=>{const f=path.join(root,decodeURIComponent(q.url.split('?')[0]));fs.readFile(f,(e,d)=>{if(e){r.statusCode=404;return r.end();}
 if(f.endsWith('.js'))r.setHeader('Content-Type','text/javascript'); r.end(d);});}).listen(8767);
(async()=>{
  const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
  const p=await b.newPage(); p.on('pageerror',e=>console.log('ERR',e.message));
  await p.goto('http://localhost:8767/bake.html'); await p.waitForFunction('window.ready===true');
  const o=await p.evaluate(s=>window.bakeHedge(s),process.argv[2]);
  fs.writeFileSync(path.join(root,'out','hedge.png'),Buffer.from(o.url.split(',')[1],'base64'));
  console.log('haie',o.W,o.H); await b.close(); srv.close();
})();
