(function () {
  const tesseractUrl = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';
  let loadPromise;

  function loadTesseract() {
    if (window.Tesseract) return Promise.resolve(window.Tesseract);
    if (!loadPromise) {
      loadPromise = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = tesseractUrl;
        script.async = true;
        script.onload = () => window.Tesseract ? resolve(window.Tesseract) : reject(new Error('Biblioteca OCR indisponível.'));
        script.onerror = () => reject(new Error('Não foi possível carregar a biblioteca OCR.'));
        document.head.appendChild(script);
      });
    }
    return loadPromise;
  }

  window.qrOpsRecognizeImage = async function (imageDataUrl) {
    const tesseract = await loadTesseract();
    const worker = await tesseract.createWorker('por');
    try {
      const result = await worker.recognize(imageDataUrl);
      return result.data.text || '';
    } finally {
      await worker.terminate();
    }
  };

  const pdfJsUrl = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
  let pdfJsPromise;
  function loadPdfJs() {
    if (window.pdfjsLib) return Promise.resolve(window.pdfjsLib);
    if (!pdfJsPromise) {
      pdfJsPromise = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = pdfJsUrl;
        script.async = true;
        script.onload = () => {
          if (!window.pdfjsLib) return reject(new Error('Biblioteca de PDF indisponível.'));
          window.pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
          resolve(window.pdfjsLib);
        };
        script.onerror = () => reject(new Error('Não foi possível carregar a biblioteca de PDF.'));
        document.head.appendChild(script);
      });
    }
    return pdfJsPromise;
  }

  window.qrOpsRecognizePdf = async function (base64Pdf) {
    const pdfjs = await loadPdfJs();
    const binary = atob(base64Pdf);
    const data = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) data[i] = binary.charCodeAt(i);
    const pdf = await pdfjs.getDocument({ data }).promise;
    if (pdf.numPages > 30) throw new Error('O PDF tem mais de 30 páginas. Divida o arquivo em lotes menores.');
    const results = [];
    let worker;
    try {
      for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber++) {
        const page = await pdf.getPage(pageNumber);
        const textContent = await page.getTextContent();
        const embeddedText = textContent.items.map(item => item.str || '').filter(Boolean).join(' ').trim();
        let text = embeddedText;
        if (!text) {
          if (!worker) {
            const tesseract = await loadTesseract();
            worker = await tesseract.createWorker('por');
          }
          const viewport = page.getViewport({ scale: 2 });
          const canvas = document.createElement('canvas');
          canvas.width = Math.ceil(viewport.width);
          canvas.height = Math.ceil(viewport.height);
          const context = canvas.getContext('2d', { willReadFrequently: true });
          await page.render({ canvasContext: context, viewport }).promise;
          const recognized = await worker.recognize(canvas.toDataURL('image/png'));
          text = (recognized.data.text || '').trim();
          canvas.width = 0;
          canvas.height = 0;
        }
        if (text) results.push('--- Página ' + pageNumber + ' ---\n' + text);
        page.cleanup();
      }
    } finally {
      if (worker) await worker.terminate();
      await pdf.destroy();
    }
    return results.join('\n\n');
  };
  const jsQrUrl = 'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js';
  let jsQrPromise;
  function loadJsQr() {
    if (window.jsQR) return Promise.resolve(window.jsQR);
    if (!jsQrPromise) {
      jsQrPromise = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = jsQrUrl;
        script.async = true;
        script.onload = () => window.jsQR ? resolve(window.jsQR) : reject(new Error('Biblioteca de leitura de QR indisponível.'));
        script.onerror = () => reject(new Error('Não foi possível carregar a biblioteca de leitura de QR.'));
        document.head.appendChild(script);
      });
    }
    return jsQrPromise;
  }

  function scanQrRegions(context, canvas, jsQR) {
    const found = [];
    const aspectRatio = canvas.width / canvas.height;
    const fullImage = context.getImageData(0, 0, canvas.width, canvas.height);
    const fullCode = jsQR(fullImage.data, fullImage.width, fullImage.height, {
      inversionAttempts: 'attemptBoth'
    });
    let fullBounds = null;
    if (fullCode && fullCode.data) {
      const points = Object.values(fullCode.location || {});
      const xs = points.filter(point => point && Number.isFinite(point.x)).map(point => point.x);
      const ys = points.filter(point => point && Number.isFinite(point.y)).map(point => point.y);
      if (xs.length && ys.length) {
        fullBounds = {
          x: Math.min(...xs),
          y: Math.min(...ys),
          width: Math.max(...xs) - Math.min(...xs),
          height: Math.max(...ys) - Math.min(...ys)
        };
      }
      found.push({ value: fullCode.data, bounds: fullBounds });
    }

    const largeCodes = fullBounds &&
      (fullBounds.width > canvas.width / 6 || fullBounds.height > canvas.height / 10);
    const columns = largeCodes
      ? (aspectRatio > 1.15 ? 6 : aspectRatio < 0.87 ? 4 : 5)
      : (aspectRatio > 1.15 ? 18 : aspectRatio < 0.87 ? 10 : 12);
    const rows = largeCodes
      ? (aspectRatio > 1.15 ? 4 : aspectRatio < 0.87 ? 6 : 5)
      : (aspectRatio > 1.15 ? 10 : aspectRatio < 0.87 ? 18 : 12);
    const cellWidth = canvas.width / columns;
    const cellHeight = canvas.height / rows;
    const overlapX = Math.ceil(cellWidth * (largeCodes ? 0.65 : 1.0));
    const overlapY = Math.ceil(cellHeight * (largeCodes ? 0.65 : 1.25));

    for (let row = 0; row < rows; row++) {
      for (let column = 0; column < columns; column++) {
        const left = Math.max(0, Math.floor(column * cellWidth - overlapX));
        const top = Math.max(0, Math.floor(row * cellHeight - overlapY));
        const right = Math.min(canvas.width, Math.ceil((column + 1) * cellWidth + overlapX));
        const bottom = Math.min(canvas.height, Math.ceil((row + 1) * cellHeight + overlapY));
        const width = right - left;
        const height = bottom - top;
        if (width < 80 || height < 80) continue;
        const imageData = context.getImageData(left, top, width, height);
        const code = jsQR(imageData.data, imageData.width, imageData.height, {
          inversionAttempts: 'attemptBoth'
        });
        if (!code || !code.data) continue;
        const points = Object.values(code.location || {});
        const xs = points.filter(point => point && Number.isFinite(point.x)).map(point => point.x);
        const ys = points.filter(point => point && Number.isFinite(point.y)).map(point => point.y);
        const bounds = xs.length && ys.length
          ? {
              x: left + Math.min(...xs),
              y: top + Math.min(...ys),
              width: Math.max(...xs) - Math.min(...xs),
              height: Math.max(...ys) - Math.min(...ys)
            }
          : null;
        found.push({ value: code.data, bounds });
      }
    }
    return found;
  }

  function mergeQrDetections(detections) {
    const merged = [];
    for (const candidate of detections) {
      const bounds = candidate.bounds;
      const duplicate = merged.some(existing => {
        if (existing.value !== candidate.value || !bounds || !existing.bounds) return false;
        const a = existing.bounds;
        const left = Math.max(a.x, bounds.x);
        const top = Math.max(a.y, bounds.y);
        const right = Math.min(a.x + a.width, bounds.x + bounds.width);
        const bottom = Math.min(a.y + a.height, bounds.y + bounds.height);
        const intersection = Math.max(0, right - left) * Math.max(0, bottom - top);
        const union = a.width * a.height + bounds.width * bounds.height - intersection;
        if (union > 0 && intersection / union >= 0.35) return true;
        const ax = a.x + a.width / 2;
        const ay = a.y + a.height / 2;
        const bx = bounds.x + bounds.width / 2;
        const by = bounds.y + bounds.height / 2;
        const distance = Math.hypot(ax - bx, ay - by);
        return distance < Math.min(Math.max(a.width, a.height), Math.max(bounds.width, bounds.height)) * 0.45;
      });
      if (!duplicate) merged.push(candidate);
    }
    return merged;
  }

  window.qrOpsScanPdfForQr = async function (base64Pdf) {
    const pdfjs = await loadPdfJs();
    const jsQR = await loadJsQr();
    const binary = atob(base64Pdf);
    const data = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) data[i] = binary.charCodeAt(i);
    const pdf = await pdfjs.getDocument({ data }).promise;
    if (pdf.numPages > 30) {
      await pdf.destroy();
      throw new Error('O PDF tem mais de 30 páginas. Divida o arquivo em lotes menores.');
    }
    const results = [];
    let detector;
    if ('BarcodeDetector' in window) {
      try {
        detector = new window.BarcodeDetector({ formats: ['qr_code'] });
      } catch (_) {
        detector = null;
      }
    }
    try {
      for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber++) {
        const page = await pdf.getPage(pageNumber);
        const viewport = page.getViewport({ scale: 2 });
        const canvas = document.createElement('canvas');
        canvas.width = Math.ceil(viewport.width);
        canvas.height = Math.ceil(viewport.height);
        const context = canvas.getContext('2d', { willReadFrequently: true });
        await page.render({ canvasContext: context, viewport }).promise;

        let detections = [];
        if (detector) {
          try {
            const detected = await detector.detect(canvas);
            detections = detected
              .filter(item => item.rawValue)
              .map(item => ({ value: item.rawValue, bounds: item.boundingBox }));
          } catch (_) {
            detections = [];
          }
        }
        // jsQR returns one code per image. Scan overlapping regions as a fallback
        // so label sheets and reports can return multiple codes from the same page.
        if (!detector || detections.length <= 1) {
          detections = mergeQrDetections([
            ...detections,
            ...scanQrRegions(context, canvas, jsQR)
          ]);
        } else {
          detections = mergeQrDetections(detections);
        }
        detections.sort((a, b) => {
          const vertical = (a.bounds?.y ?? 0) - (b.bounds?.y ?? 0);
          return Math.abs(vertical) > 2 ? vertical : (a.bounds?.x ?? 0) - (b.bounds?.x ?? 0);
        });
        for (const detection of detections) {
          const value = detection.value;
          let imageBase64 = '';
          const bounds = detection.bounds;
          if (bounds) {
            const pad = Math.max(12, Math.round(Math.max(bounds.width, bounds.height) * 0.12));
            const left = Math.max(0, Math.floor(bounds.x - pad));
            const top = Math.max(0, Math.floor(bounds.y - pad));
            const right = Math.min(canvas.width, Math.ceil(bounds.x + bounds.width + pad));
            const bottom = Math.min(canvas.height, Math.ceil(bounds.y + bounds.height + pad));
            const crop = document.createElement('canvas');
            crop.width = Math.max(1, right - left);
            crop.height = Math.max(1, bottom - top);
            crop.getContext('2d').drawImage(canvas, left, top, crop.width, crop.height, 0, 0, crop.width, crop.height);
            imageBase64 = crop.toDataURL('image/png').split(',')[1];
            crop.width = 0;
            crop.height = 0;
          }
          results.push({ value, pageNumber, totalPages: pdf.numPages, imageBase64 });
        }
        canvas.width = 0;
        canvas.height = 0;
        page.cleanup();
      }
      return JSON.stringify(results);
    } finally {
      await pdf.destroy();
    }
  };

})();

