const defaultProducts = [
  { id: 'multi', name: 'Daily Multivitamin', category: 'Vitamins', note: 'Everyday support', size: '60 tablets', price: 8500, tag: 'Bestseller', accent: '#b5d754', wash: '#edf3e4', image: 'multivitamin.jpg', description: 'A daily multivitamin in a 60-tablet pack. Check the product packaging for its complete ingredient list, directions and important information.' },
  { id: 'vitc', name: 'Vitamin C 1000 mg', category: 'Vitamins', note: 'Immune support', size: '30 tablets', price: 5200, tag: 'Popular', accent: '#e7785f', wash: '#f7ece5', image: 'Vitamin-C-1000mg-Mega-C-1.webp', description: 'Vitamin C tablets labelled 1000 mg, supplied in a 30-tablet pack. Refer to the packaging for ingredients, directions and warnings.' },
  { id: 'omega', name: 'Omega-3 Fish Oil', category: 'Vitamins', note: 'Daily wellness', size: '60 softgels', price: 17500, tag: '', accent: '#85aab1', wash: '#eaf0ef', image: 's-l1600.webp', description: 'Omega-3 fish oil softgels in a 60-softgel pack. Check the label for the full product details, ingredients and directions.' },
  { id: 'thermo', name: 'Digital Thermometer', category: 'First aid', note: 'Quick, clear readings', size: '1 device', price: 7800, tag: 'Home essential', accent: '#83b4a0', wash: '#e9f1eb', image: 'images.jpg', description: 'A digital thermometer for home use. Follow the device instructions for use, cleaning and storage.' },
  { id: 'firstaid', name: 'Antiseptic First Aid', category: 'First aid', note: 'For minor cuts and scrapes', size: '250 ml', price: 4300, tag: '', accent: '#e59a69', wash: '#f5eee4', image: 'Antiseptic First Aid.jpg', description: 'A 250 ml antiseptic product listed for minor cuts and scrapes. Read the packaging for directions, precautions and intended use.' },
  { id: 'sun', name: 'Daily Sunscreen SPF 50', category: 'Personal care', note: 'Broad spectrum care', size: '50 ml', price: 6800, tag: 'New', accent: '#e4c455', wash: '#f5f1de', image: 'Daily Sunscreen SPF 50.jpg', description: 'A 50 ml sunscreen labelled SPF 50. Follow the product label for application directions, reapplication and precautions.' },
  { id: 'balm', name: 'Soothing Skin Balm', category: 'Personal care', note: 'Everyday moisture', size: '100 ml', price: 6100, tag: '', accent: '#d38975', wash: '#f4ebe6', image: 'Soothing Skin Balm.jpg', description: 'A 100 ml skin balm for everyday moisture. Review the packaging for its ingredients, directions and suitability for your skin.' },
  { id: 'pain', name: 'Pain Relief Tablets', category: 'Pain relief', note: 'For occasional aches', size: '10 tablets', price: 1000, tag: '', accent: '#6a9d89', wash: '#e9f0e8', image: '1a8ee9606909489d6cb71348387babba.jpg', description: 'Pain relief tablets in a 10-tablet pack. The active ingredient and strength are not specified here; check the package and ask a pharmacist before use.' },
  { id: 'sudrex', name: 'Sudrex Tablets', category: 'Pain relief', note: 'For occasional aches', size: 'Tablets', price: 2000, tag: '', accent: '#6a9d89', wash: '#e9f0e8', image: 'sudrex.jpg', description: 'Sudrex tablets. Check the product packaging for the active ingredients, strength, pack size and directions. Ask a pharmacist before use.' },
  { id: 'cream', name: 'Cream', category: 'Personal care', note: 'Everyday personal care', size: 'See product packaging', price: 1800, tag: '', accent: '#d38975', wash: '#f4ebe6', image: 'vaseline.jpg', description: 'A personal care cream. Check the product packaging for its intended use, ingredients, pack size and directions.' }
];

function validateProductCatalog(catalog) {
  if (!Array.isArray(catalog) || catalog.some(product =>
    !product ||
    typeof product.id !== 'string' ||
    !product.id.trim() ||
    typeof product.name !== 'string' ||
    !product.name.trim() ||
    typeof product.category !== 'string' ||
    !product.category.trim() ||
    typeof product.note !== 'string' ||
    !product.note.trim() ||
    typeof product.size !== 'string' ||
    !product.size.trim() ||
    !Number.isSafeInteger(product.price) ||
    product.price < 1 ||
    typeof product.image !== 'string' ||
    !product.image.trim() ||
    typeof product.description !== 'string' ||
    !product.description.trim()
  )) {
    throw new Error('The saved PharmaGo product catalog has an invalid format.');
  }
  const ids = catalog.map(product => product.id);
  if (new Set(ids).size !== ids.length) {
    throw new Error('The saved PharmaGo product catalog contains duplicate product IDs.');
  }
  return catalog;
}

function readProductCatalog() {
  const savedCatalog = localStorage.getItem('pharmago-products');
  return savedCatalog === null ? defaultProducts : validateProductCatalog(JSON.parse(savedCatalog));
}

const products = readProductCatalog();

window.saveProductCatalog = function (catalog) {
  const validCatalog = validateProductCatalog(catalog);
  localStorage.setItem('pharmago-products', JSON.stringify(validCatalog));
};
