const sharp = require('./node_modules/sharp');
const fs = require('fs');
const path = require('path');

const BASE = 'D:/projects/hotel_lux_profile';

// Files that didn't compress well - try palette quantization
const targets = [
  { rel: 'lib/assets/stayfixjob_chat_background_dark_doodle.png', palette: true, colors: 256 },
  { rel: 'lib/assets/icon/heroimg.png', palette: true, colors: 256 },
  { rel: 'lib/assets/icon/stayfixjob.png', palette: true, colors: 256 },
];

async function optimize({ rel, palette, colors }) {
  const fullPath = path.join(BASE, rel);
  const originalSize = fs.statSync(fullPath).size;
  const meta = await sharp(fullPath).metadata();
  console.log(`${path.basename(rel)}: ${meta.width}x${meta.height}, channels:${meta.channels}, hasAlpha:${meta.hasAlpha}`);

  // Try palette quantization (reduces to indexed color)
  await sharp(fullPath)
    .png({
      quality: 100,
      compressionLevel: 9,
      palette: true,
      colors: colors,
      dither: 1.0,
      effort: 10,
    })
    .toFile(fullPath + '.opt.png');

  const optSize = fs.statSync(fullPath + '.opt.png').size;
  const saved = ((originalSize - optSize) / originalSize * 100).toFixed(1);
  console.log(`  palette(${colors}): ${(originalSize/1024).toFixed(0)}KB → ${(optSize/1024).toFixed(0)}KB (${saved}% saved)`);

  if (optSize < originalSize) {
    fs.copyFileSync(fullPath + '.opt.png', fullPath);
    console.log(`  -> Replaced!`);
  } else {
    console.log(`  -> No improvement, keeping original`);
  }
  fs.unlinkSync(fullPath + '.opt.png');
}

(async () => {
  for (const t of targets) {
    try {
      await optimize(t);
    } catch (e) {
      console.error(`Error:`, e.message);
    }
  }
})();
