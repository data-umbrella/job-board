////////
// Link inputs with preview
////////

// Add date
const dateEl = document.querySelector('#preview-date')
const date = moment().format('MMMM D');
dateEl.innerText = date

// Add text inputs
const textInputs = Array.from(document.querySelectorAll('input'));
const textBoxes = Array.from(document.querySelectorAll('textarea'));
const inputs = textInputs.concat(textBoxes);
inputs.forEach(input => input.addEventListener('input', updateValue));

function updateValue(e) {
  const id = e.target.id
  const previewId = id.replace('original', 'preview')
  const el = document.querySelector(`#${previewId}`)
  el.innerHTML = e.target.value;
}

// Update job type
const sel = document.querySelector('#original-type')
sel.addEventListener('change', function() {
  const text = sel.options[sel.selectedIndex].text
  const newSel = document.querySelector('#preview-type')
  newSel.innerHTML = "/ " + text
})

// Update apply link
const applyLink = document.querySelector('#application')
applyLink.addEventListener('input', function(e) {
  const text = e.target.value
  const newLink = document.querySelector('#preview-application')
  const newHTML = `<a href="${text}" target="_blank"><button class="bg-${accentColor}-500 hover:bg-${accentColor}-700 text-white text-xl lg:text-base font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline" type="button">Apply to job</button></a>`
  newLink.innerHTML = newHTML;
})

// Update company link
const companyLink = document.querySelector('#website')
companyLink.addEventListener('input', function(e) {
  const text = e.target.value
  const newLink = document.querySelector('#preview-company-link')
  const newHTML = `<a href="${text}" target="_blank"><button class="bg-transparent hover:bg-${accentColor}-500 text-${accentColor}-700 hover:text-white text-xl lg:text-base font-semibold py-2 px-4 focus:outline-none focus:shadow-outline border border-${accentColor}-500 hover:border-transparent rounded" type="button">Learn about the company</button></a>`
  newLink.innerHTML = newHTML;
})


////////
// Refresh markdown preview
////////
let descBox = new SimpleMDE({
  element: document.getElementById("original-description"),
  hideIcons: ["quote", "image",],
  status: false,
});

let previewTimer = setInterval(updateMarkdown, 5000)

function updateMarkdown() {
  const descOutput = document.querySelector('#preview-description')
  descOutput.innerHTML = descBox.markdown(descBox.value())
}

////////
// Prevent large files from being uploaded && displays logo preview
////////
const uploadField = document.getElementById("logo-upload");

uploadField.onchange = function(e) {
  if(this.files[0].size > 1097152) {
     alert("File is too big!");
     this.value = "";
  };

  const imgURL = URL.createObjectURL(e.target.files[0]);

  const newLogo = document.querySelector('#preview-logo')
  const logoHTML = `<img src="${imgURL}" style="max-width: 80px; max-height: 100px">`
  newLogo.innerHTML = logoHTML

  newLogo.onload = function() {
    URL.revokeObjectURL(imgURL) // free memory
  }

};
