(function () {
    'use strict';

    /* ---------- Toast ---------- */
    const toastEl = document.getElementById('toast');
    let toastTimer;

    function toast(message) {
        toastEl.textContent = message;
        toastEl.classList.add('show');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => toastEl.classList.remove('show'), 2200);
    }

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / 1048576).toFixed(2) + ' MB';
    }

    /* ---------- Formularz uploadu ---------- */
    function initUploadForm() {
        const form = document.getElementById('uploadForm');
        if (!form) return;

        const maxSize = parseInt(form.dataset.maxSize, 10);
        const input = document.getElementById('csvfile');
        const dropzone = document.getElementById('dropzone');
        const fileName = document.getElementById('fileName');
        const submitBtn = document.getElementById('submitBtn');
        const defaultText = fileName.textContent;

        function setState(text, enabled) {
            fileName.textContent = text;
            submitBtn.disabled = !enabled;
        }

        function onFileChosen() {
            const file = input.files[0];
            if (!file) return setState(defaultText, false);
            if (file.size === 0) return setState('❌ ' + file.name + ' – plik jest pusty', false);
            if (file.size > maxSize) {
                return setState('❌ ' + file.name + ' – plik za duży (' + formatSize(file.size) + ')', false);
            }
            setState('📎 ' + file.name + ' (' + formatSize(file.size) + ')', true);
        }

        input.addEventListener('change', onFileChosen);

        ['dragenter', 'dragover'].forEach(ev => dropzone.addEventListener(ev, e => {
            e.preventDefault();
            dropzone.classList.add('drag');
        }));
        ['dragleave', 'drop'].forEach(ev => dropzone.addEventListener(ev, e => {
            e.preventDefault();
            dropzone.classList.remove('drag');
        }));
        dropzone.addEventListener('drop', e => {
            if (e.dataTransfer.files.length) {
                input.files = e.dataTransfer.files;
                onFileChosen();
            }
        });

        form.addEventListener('submit', () => {
            submitBtn.disabled = true;
            submitBtn.classList.add('loading');
            submitBtn.querySelector('.label').textContent = 'Przetwarzanie…';
        });
    }

    /* ---------- Kopiowanie do schowka ---------- */
    async function copyText(text) {
        try {
            await navigator.clipboard.writeText(text);
        } catch (_) {
            // fallback dla http / starszych przeglądarek
            const tmp = document.createElement('textarea');
            tmp.value = text;
            document.body.appendChild(tmp);
            tmp.select();
            document.execCommand('copy');
            tmp.remove();
        }
    }

    function initCopyButtons() {
        document.querySelectorAll('[data-copy]').forEach(btn => btn.addEventListener('click', async () => {
            const el = document.querySelector(btn.dataset.copy);
            await copyText('value' in el ? el.value : el.textContent);
            toast('Skopiowano do schowka');
        }));
    }

    /* ---------- Pobieranie pliku ---------- */
    function initDownload() {
        const btn = document.getElementById('downloadBtn');
        if (!btn) return;

        btn.addEventListener('click', () => {
            const text = document.querySelector(btn.dataset.source).value;
            const blob = new Blob([text], { type: 'text/csv;charset=utf-8;' });
            const link = document.createElement('a');
            link.href = URL.createObjectURL(blob);
            link.download = btn.dataset.filename;
            document.body.appendChild(link);
            link.click();
            link.remove();
            setTimeout(() => URL.revokeObjectURL(link.href), 1000);
            toast('Pobieranie pliku rozpoczęte');
        });
    }

    /* ---------- Start ---------- */
    initUploadForm();
    initCopyButtons();
    initDownload();

    const success = document.getElementById('successAlert');
    if (success) success.scrollIntoView({ behavior: 'smooth', block: 'start' });
})();

