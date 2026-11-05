const fs = require('fs');
const s = fs.readFileSync('D:/Explorer/MAYUNDO/KEY PROJECTS/DropOff/workers/src/index.ts','utf8');
let i = s.indexOf("app.post('/jobs'");
if(i<0) i = s.indexOf('app.post("/jobs"');
if(i<0){console.log('x');process.exit(0);}
const t = s.slice(i);
const j = t.indexOf('try');
if(j<0){console.log('y');process.exit(0);}
console.log(t.slice(j, j+280));
