const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const http=require('http'),fs=require('fs'),path=require('path');
const root=process.argv[2];
const srv=http.createServer((q,r)=>{const f=path.join(root,decodeURIComponent(q.url.split('?')[0]));fs.readFile(f,(e,d)=>{if(e){r.statusCode=404;return r.end();}r.end(d);});}).listen(8765);
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
  const p = await b.newPage({viewport:{width:2400,height:1080}});
  p.on('console',m=>console.log(m.text())); p.on('pageerror',e=>console.log('ERR',e.message));
  await p.goto('http://localhost:8765/world2.html');
  await p.waitForFunction('window.ready===true',null,{timeout:120000});
  const shots=JSON.parse(process.argv[3]);
  for(const s of shots){
    await p.evaluate((s)=>{const m=getMap();let car=null,yaw=0;
      const P=s.pos?{x:s.pos[0],z:s.pos[1]}:(s.at?m.pois.find(p=>p.name==s.at):m.start);const gy=getH(P.x,P.z);
      yaw=s.yaw||0;const fx=Math.sin(yaw),fz=-Math.cos(yaw);
      car=[P.x,gy+0.07,P.z];
      const eye=s.eye?[P.x+s.eye[0],gy+s.eye[1],P.z+s.eye[2]]:[P.x-fx*7.6,gy+2.1,P.z-fz*7.6];
      const tgt=s.tgt?[P.x+s.tgt[0],gy+s.tgt[1],P.z+s.tgt[2]]:[P.x,gy+1.35,P.z];
      render(eye,tgt,s.fov||0.9,s.nocar?null:car,yaw);},s);
    await p.screenshot({path:s.name+'.png'});
  }
  await b.close(); srv.close();
})();
