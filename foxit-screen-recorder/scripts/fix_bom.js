const fs = require('fs');
const path = 'C:\\Users\\vboxuser\\.openclaw\\workspace\\skills\\foxit-screen-recorder\\SKILL.md';
let content = fs.readFileSync(path, 'utf8');

const lines = content.split('\n');
let endIdx = -1;
for (let i = 1; i < lines.length; i++) {
  if (lines[i].trim() === '---') { endIdx = i; break; }
}

let rest = lines.slice(endIdx + 1).join('\n').trimStart();
rest = rest.replace(/^# Foxit Screen Recorder \(.*?\)/m, '# Foxit Screen Recorder (福昕录屏)');

const newFront = '---\n'
  + 'name: foxit-screen-recorder\n'
  + 'description: Install, launch, and control Foxit Screen Recorder (福昕录屏) via terminal. Use when the user wants to: (1) record their screen, (2) start/stop a screen recording, (3) install Foxit Screen Recorder from the official site, or (4) capture desktop activity. Triggers: 录屏, screen record, 福昕录屏, 录制屏幕, 录制, start recording, stop recording.\n'
  + '---\n';

const newContent = newFront + rest;
fs.writeFileSync(path, newContent, 'utf8');
console.log('Done!');
const verify = fs.readFileSync(path, 'utf8').split('\n').slice(0, 8);
console.log(verify.join('\n'));
