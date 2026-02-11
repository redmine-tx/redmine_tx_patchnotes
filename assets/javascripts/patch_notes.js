function showSkipForm(issueId) {
  document.getElementById('patch-note-skip-form-container').style.display = 'block';
  document.getElementById('patch-note-actions').style.display = 'none';
}

function hideSkipForm() {
  document.getElementById('patch-note-skip-form-container').style.display = 'none';
  document.getElementById('patch-note-actions').style.display = 'block';
}

function cancelPatchNoteForm() {
  document.getElementById('patch-note-form-container').innerHTML = '';
  document.getElementById('patch-note-form-container').style.display = 'none';
  var actions = document.getElementById('patch-note-actions');
  if (actions) actions.style.display = 'block';
}

function cancelEditPatchNote(id) {
  var editContainer = document.getElementById('patch-note-edit-container-' + id);
  if (editContainer) {
    editContainer.innerHTML = '';
    editContainer.style.display = 'none';
  }
  var display = document.getElementById('patch-note-display-' + id);
  if (display) display.style.display = 'block';
}
