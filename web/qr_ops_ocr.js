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
        script.onload = () => window.Tesseract ? resolve(window.Tesseract) : reject(new Error('Biblioteca OCR indisponÃ­vel.'));
        script.onerror = () => reject(new Error('NÃ£o foi possÃ­vel carregar a biblioteca OCR.'));
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
    const seen = new Set();
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
        if (detections.length === 0) {
          const imageData = context.getImageData(0, 0, canvas.width, canvas.height);
          const code = jsQR(imageData.data, imageData.width, imageData.height, {
            inversionAttempts: 'attemptBoth'
          });
          if (code && code.data) {
            const points = Object.values(code.location || {});
            const xs = points.filter(point => point && Number.isFinite(point.x)).map(point => point.x);
            const ys = points.filter(point => point && Number.isFinite(point.y)).map(point => point.y);
            const bounds = xs.length && ys.length
              ? { x: Math.min(...xs), y: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys) }
              : null;
            detections = [{ value: code.data, bounds }];
          }
        }
        for (const detection of detections) {
          const value = detection.value;
          const key = pageNumber + '\\u0000' + value;
          if (seen.has(key)) continue;
          seen.add(key);
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

