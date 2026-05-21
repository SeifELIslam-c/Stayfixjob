const sharp = require('./node_modules/sharp');
const fs = require('fs');
const path = require('path');

const images = [
  'lib/assets/absenceheroimg.png',
  'lib/assets/calendrierheroimg.png',
  'lib/assets/conditionheroimg.png',
  'lib/assets/disponibiliteheroimg.png',
  'lib/assets/homepageimghero.png',
  'lib/assets/horlageheroimg.png',
  'lib/assets/monprofileimghero.png',
  'lib/assets/selectionheroimg.png',
  'lib/assets/settingsheroimg.png',
  'lib/assets/stayfixjob_chat_background_dark_doodle.png',
  'lib/assets/icon/heroimg.png',
  'lib/assets/icon/stayfixjob.png',
];

const BASE = 'D:/projects/hotel_lux_profile';

async function optimize(relPath) {
  const fullPath = path.join(BASE, relPath);
  const originalSize = fs.statSync(fullPath).size;

  // Get image dimensions first
  const meta = await sharp(fullPath).metadata();
  const isIcon = relPath.includes('/icon/');

  // For icons keep full resolution, for hero images cap at 1200px wide
  const maxWidth = isIcon ? meta.width : 1200;

  await sharp(fullPath)
    .resize(maxWidth, null, { withoutEnlargement: true, fit: 'inside' })
    .png({
      quality: 90,
      compressionLevel: 9,
      palette: false,
      effort: 10,
    })
    .toFile(fullPath + '.opt.png');

  const optSize = fs.statSync(fullPath + '.opt.png').size;

  // Only replace if the optimized version is smaller
  if (optSize < originalSize) {
    fs.copyFileSync(fullPath + '.opt.png', fullPath);
  }
  fs.unlinkSync(fullPath + '.opt.png');

  const finalSize = fs.statSync(fullPath).size;
  const saved = ((originalSize - finalSize) / originalSize * 100).toFixed(1);
  console.log(`${path.basename(relPath)}: ${(originalSize/1024).toFixed(0)}KB → ${(finalSize/1024).toFixed(0)}KB (${saved}% saved)`);
}

(async () => {
  for (const img of images) {
    try {
      await optimize(img);
    } catch (e) {
      console.error(`Error on ${img}:`, e.message);
    }
  }
})();
