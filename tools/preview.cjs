const { chromium } = require('C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs = require('node:fs');
(async () => {
  const browser = await chromium.launch({headless:true, executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
  const page = await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
  const errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.goto('http://127.0.0.1:8765');
  await page.waitForSelector('flutter-view');
  await page.waitForTimeout(5000);
  fs.mkdirSync('release/screenshots',{recursive:true});
  await page.screenshot({path:'release/screenshots/lich-tap.png'});
  await page.mouse.click(195,803);await page.waitForTimeout(700);
  await page.screenshot({path:'release/screenshots/tien-do.png'});
  await page.mouse.click(326,803);await page.waitForTimeout(700);
  await page.screenshot({path:'release/screenshots/du-lieu.png'});
  console.log(JSON.stringify({errors}));
  await browser.close();
})();
