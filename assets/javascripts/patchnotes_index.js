// === Tab Switching ===
document.addEventListener('DOMContentLoaded', function() {
    document.querySelectorAll('.tab-link').forEach(function(link) {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            var targetId = this.getAttribute('data-tab');

            document.querySelectorAll('.tab-link').forEach(function(l) { l.classList.remove('active'); });
            document.querySelectorAll('.tab-panel').forEach(function(p) { p.classList.remove('active'); });

            this.classList.add('active');
            document.getElementById(targetId).classList.add('active');

            // Update URL for bookmarking
            var url = new URL(window.location);
            url.searchParams.set('tab', targetId.replace('inner-tab-', ''));
            history.replaceState(null, '', url.toString());
        });
    });
});

// === HTML to Plain Text ===
function htmlToPlainText(html) {
    var tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;

    tempDiv.querySelectorAll('br').forEach(function(br) { br.replaceWith('\n'); });
    tempDiv.querySelectorAll('p, div, li').forEach(function(el) {
        el.appendChild(document.createTextNode('\n'));
    });

    return tempDiv.textContent || tempDiv.innerText || '';
}

// === Excel Export ===
async function exportPatchNotesToExcel(part, type) {
    part = part || 1;
    type = type || 'public';

    var listId = type === 'internal'
        ? 'patch-notes-list-internal-' + part
        : 'patch-notes-list-public-' + part;
    var patchNotesList = document.getElementById(listId);

    if (!patchNotesList) {
        alert('패치노트 목록을 찾을 수 없습니다.');
        return;
    }

    try {
        var workbook = new ExcelJS.Workbook();
        var worksheet = workbook.addWorksheet('패치노트');

        worksheet.columns = [
            { header: 'ID', key: 'id', width: 10 },
            { header: '유형', key: 'tracker', width: 12 },
            { header: '범주', key: 'category', width: 15 },
            { header: '제목', key: 'subject', width: 40 },
            { header: '디테일', key: 'detail', width: 60 },
            { header: '담당자', key: 'assignee', width: 15 },
            { header: '상태', key: 'status', width: 12 },
            { header: '우선순위', key: 'priority', width: 12 },
            { header: '진행율', key: 'done_ratio', width: 10 }
        ];

        worksheet.getRow(1).font = { bold: true };
        worksheet.getRow(1).fill = {
            type: 'pattern',
            pattern: 'solid',
            fgColor: { argb: 'FFE0E0E0' }
        };

        var items = patchNotesList.getElementsByClassName('note-item');
        Array.from(items).forEach(function(item) {
            var titleElement = item.querySelector('.note-item-title');
            var contentElement = item.querySelector('.note-item-content');

            var issueId = item.dataset.issueId || '';
            var issueUrl = item.dataset.issueUrl || '';
            var tracker = item.dataset.tracker || '';
            var category = item.dataset.category || '';
            var status = item.dataset.status || '';
            var priority = item.dataset.priority || '';
            var doneRatio = item.dataset.doneRatio || '0';
            var assignee = item.dataset.assignee || '';

            var titleText = titleElement.textContent.trim();
            var subject = titleText
                .replace(/#\d+/, '')
                .replace(/\(담당자:.*?\)/, '')
                .trim();

            var detail = htmlToPlainText(contentElement.innerHTML);

            var row = worksheet.addRow({
                id: issueId,
                tracker: tracker,
                category: category,
                subject: subject,
                detail: detail.trim(),
                assignee: assignee,
                status: status,
                priority: priority,
                done_ratio: doneRatio + '%'
            });

            if (issueUrl) {
                row.getCell('id').value = {
                    text: issueId,
                    hyperlink: issueUrl,
                    tooltip: '일감 보기'
                };
                row.getCell('id').font = { color: { argb: 'FF0066CC' }, underline: true };
            }

            row.getCell('detail').alignment = { wrapText: true, vertical: 'top' };
            row.eachCell(function(cell) {
                if (!cell.alignment) cell.alignment = {};
                cell.alignment.vertical = 'top';
            });
        });

        // Read version name from data attribute
        var container = document.querySelector('[data-version-name]');
        var versionName = container ? container.dataset.versionName : 'unknown';
        var typeLabel = type === 'internal' ? '내부용' : '공개용';
        var fileName = '패치노트_' + versionName + '_Part' + part + '_' + typeLabel + '.xlsx';

        var buffer = await workbook.xlsx.writeBuffer();
        var blob = new Blob([buffer], {
            type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        });
        var url = URL.createObjectURL(blob);
        var a = document.createElement('a');
        a.href = url;
        a.download = fileName;
        a.click();
        URL.revokeObjectURL(url);

        alert('엑셀 파일이 다운로드되었습니다.');
    } catch (error) {
        console.error('엑셀 생성 실패:', error);
        alert('엑셀 생성 중 오류가 발생했습니다: ' + error.message);
    }
}

// === PDF Export ===
async function exportPatchNotesToPdf(part, type) {
    part = part || 1;
    type = type || 'public';

    var listId = type === 'internal'
        ? 'patch-notes-list-internal-' + part
        : 'patch-notes-list-public-' + part;
    var patchNotesList = document.getElementById(listId);

    if (!patchNotesList) {
        alert('패치노트 목록을 찾을 수 없습니다.');
        return;
    }

    try {
        // Clone the list to avoid modifying the original DOM
        var clone = patchNotesList.cloneNode(true);
        clone.removeAttribute('id');

        // Convert relative image URLs to absolute and then to data URLs
        var images = clone.querySelectorAll('img');
        await Promise.all(Array.from(images).map(function(img) {
            var src = img.getAttribute('src');
            var absoluteSrc = src.startsWith('http') ? src : window.location.origin + src;
            return convertImageToDataURL(absoluteSrc).then(function(dataUrl) {
                img.setAttribute('src', dataUrl);
            });
        }));

        // Remove link hrefs so they don't show as blue underlined text in PDF
        clone.querySelectorAll('a').forEach(function(a) {
            a.removeAttribute('href');
            a.style.color = '#1a73e8';
            a.style.textDecoration = 'none';
        });

        // Apply inline styles to cloned elements for PDF rendering
        var noteItems = clone.querySelectorAll('.note-item');
        noteItems.forEach(function(item) {
            item.style.listStyle = 'none';
            item.style.marginBottom = '12px';
            item.style.padding = '12px 15px';
            item.style.border = '1px solid #e0e0e0';
            item.style.borderLeft = '4px solid ' + (item.style.borderLeftColor || '#999');
            item.style.borderRadius = '4px';
            item.style.background = '#fff';
            item.style.pageBreakInside = 'avoid';
        });

        clone.querySelectorAll('.note-item-header').forEach(function(header) {
            header.style.display = 'flex';
            header.style.alignItems = 'center';
            header.style.flexWrap = 'wrap';
            header.style.gap = '8px';
            header.style.marginBottom = '6px';
        });

        clone.querySelectorAll('.pn-tracker-badge').forEach(function(badge) {
            badge.style.display = 'inline-block';
            badge.style.padding = '1px 8px';
            badge.style.borderRadius = '3px';
            badge.style.fontSize = '0.75em';
            badge.style.fontWeight = 'bold';
            badge.style.color = '#fff';
            badge.style.whiteSpace = 'nowrap';
        });

        clone.querySelectorAll('.note-item-title').forEach(function(title) {
            title.style.fontSize = '1em';
            title.style.fontWeight = '600';
            title.style.color = '#333';
        });

        clone.querySelectorAll('.pn-assignee-tag').forEach(function(tag) {
            tag.style.display = 'inline-block';
            tag.style.padding = '1px 8px';
            tag.style.borderRadius = '3px';
            tag.style.fontSize = '0.75em';
            tag.style.color = '#555';
            tag.style.background = '#f0f0f0';
            tag.style.border = '1px solid #ddd';
            tag.style.whiteSpace = 'nowrap';
        });

        clone.querySelectorAll('.note-item-content').forEach(function(content) {
            content.style.padding = '8px 10px';
            content.style.marginTop = '4px';
            content.style.background = '#fafbfc';
            content.style.borderRadius = '3px';
            content.style.border = '1px solid #f0f0f0';
            content.style.fontSize = '0.92em';
            content.style.color = '#444';
        });

        // Wrap in a container with title
        var container = document.createElement('div');
        container.style.fontFamily = 'Arial, sans-serif';
        container.style.padding = '10px';

        var versionEl = document.querySelector('[data-version-name]');
        var versionName = versionEl ? versionEl.dataset.versionName : '';
        var typeLabel = type === 'internal' ? '내부 참조용 패치노트' : '공개용 패치노트';

        var titleEl = document.createElement('h2');
        titleEl.textContent = versionName + ' - ' + typeLabel + ' (Part #' + part + ')';
        titleEl.style.color = type === 'internal' ? '#d63' : '#1a73e8';
        titleEl.style.borderBottom = '2px solid ' + (type === 'internal' ? '#d63' : '#1a73e8');
        titleEl.style.paddingBottom = '8px';
        titleEl.style.fontSize = '1.15em';

        container.appendChild(titleEl);
        container.appendChild(clone);

        // Generate PDF
        var fileName = '패치노트_' + versionName + '_Part' + part + '_' + (type === 'internal' ? '내부용' : '공개용') + '.pdf';

        var opt = {
            margin: [10, 10, 10, 10],
            filename: fileName,
            image: { type: 'jpeg', quality: 0.95 },
            html2canvas: { scale: 2, useCORS: true, logging: false },
            jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' },
            pagebreak: { mode: ['avoid-all', 'css', 'legacy'] }
        };

        await html2pdf().set(opt).from(container).save();

        alert('PDF 파일이 다운로드되었습니다.');
    } catch (error) {
        console.error('PDF 생성 실패:', error);
        alert('PDF 생성 중 오류가 발생했습니다: ' + error.message);
    }
}

// === Clipboard Copy ===
function copyPatchNotes(part, type) {
    part = part || 1;
    type = type || 'public';

    var listId = type === 'internal'
        ? 'patch-notes-list-internal-' + part
        : 'patch-notes-list-public-' + part;
    var patchNotesList = document.getElementById(listId);

    if (!patchNotesList) {
        alert('패치노트 목록을 찾을 수 없습니다.');
        return;
    }

    var items = patchNotesList.getElementsByClassName('note-item');

    // Convert images to data URLs, then copy as HTML
    Promise.all(Array.from(items).map(function(item) {
        var title = item.querySelector('.note-item-title').innerHTML;
        var content = item.querySelector('.note-item-content').innerHTML;

        // Collect image conversion promises
        var imgElements = item.querySelector('.note-item-content').querySelectorAll('img');
        var imgPromises = Array.from(imgElements).map(function(img) {
            var src = img.getAttribute('src');
            var absoluteSrc = src.startsWith('http') ? src : window.location.origin + src;
            return convertImageToDataURL(absoluteSrc).then(function(dataUrl) {
                return { original: src, dataUrl: dataUrl };
            });
        });

        return Promise.all(imgPromises).then(function(imgResults) {
            imgResults.forEach(function(result) {
                content = content.split(result.original).join(result.dataUrl);
            });
            return '<div class="note-item">' +
                '<strong class="note-item-title">' + title + '</strong>' +
                '<div class="note-item-content">' + content + '</div>' +
                '</div>';
        });
    })).then(function(htmlContents) {
        var htmlString = htmlContents.join('');

        // Try modern clipboard API first, fallback to execCommand
        if (navigator.clipboard && typeof ClipboardItem !== 'undefined') {
            var blob = new Blob([htmlString], { type: 'text/html' });
            navigator.clipboard.write([new ClipboardItem({ 'text/html': blob })]).then(function() {
                alert('패치노트가 클립보드에 복사되었습니다.');
            }).catch(function() {
                fallbackCopy(htmlString);
            });
        } else {
            fallbackCopy(htmlString);
        }
    });
}

function fallbackCopy(htmlString) {
    var tempDiv = document.createElement('div');
    tempDiv.style.position = 'fixed';
    tempDiv.style.opacity = '0';
    tempDiv.style.pointerEvents = 'none';
    tempDiv.innerHTML = htmlString;
    document.body.appendChild(tempDiv);

    var range = document.createRange();
    range.selectNode(tempDiv);
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    try {
        document.execCommand('copy');
        alert('패치노트가 클립보드에 복사되었습니다.');
    } catch (err) {
        console.error('클립보드 복사 실패:', err);
        alert('클립보드 복사에 실패했습니다.');
    }

    selection.removeAllRanges();
    document.body.removeChild(tempDiv);
}

function convertImageToDataURL(imgUrl) {
    return fetch(imgUrl).then(function(response) {
        return response.blob();
    }).then(function(blob) {
        return new Promise(function(resolve) {
            var reader = new FileReader();
            reader.onloadend = function() { resolve(reader.result); };
            reader.readAsDataURL(blob);
        });
    }).catch(function(err) {
        console.error('이미지 변환 실패:', err);
        return imgUrl;
    });
}
