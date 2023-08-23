////////
// Link inputs with preview
////////

// Spam Math Check
const submitButton = document.querySelector('#checkout-button');
const spamInput = document.querySelector('#spam-check');
spamInput.addEventListener('input', function(e) {
  if (e.target.value == 13) {
    submitButton.disabled = false;
  }
});

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
// let descBox = new SimpleMDE({
//   element: document.getElementById("original-description"),
//   hideIcons: ["quote", "image",],
//   status: false,
// });
//
// let previewTimer = setInterval(updateMarkdown, 5000)
//
// function updateMarkdown() {
//   const descOutput = document.querySelector('#preview-description')
//   descOutput.innerHTML = descBox.markdown(descBox.value())
// }

////////
// Quill WYSIWYG Editor Code
////////

// Setup toolbar options
var toolbarOptions = [
  [{ 'header': [1, 2, 3, false] }],
  ['bold', 'italic', 'underline'],        // toggled buttons

  // [{ 'header': 1 }, { 'header': 2 }],               // custom button values
  [{ 'list': 'ordered'}, { 'list': 'bullet' }],

  ['clean']                                         // remove formatting button
];

// Initialize editor
var quill = new Quill('#editor', {
  modules: {
    toolbar: toolbarOptions
  },
  theme: 'snow'
});

// Update hidden field
const hidden = document.querySelector('#hiddenArea');
const descOutput = document.querySelector('#preview-description')
let quillVal = quill.container.firstChild.innerHTML;
hidden.value = quillVal;

quill.on('text-change', function() {
  let quillVal = quill.container.firstChild.innerHTML;
  hidden.value = quillVal;
  descOutput.innerHTML = quillVal;
});

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


////////
// Featured job
////////
// const featuredOption = document.querySelector('#featured-option')
// featuredOption.addEventListener('change', function() {
//   const text = featuredOption.options[featuredOption.selectedIndex].text
//   const previewCard = document.querySelector('#preview-card')
//   if (text == "Yes") {
//     previewCard.classList.remove("bg-white")
//     previewCard.classList.add("bg-yellow-100")
//     dateEl.innerHTML = "<p class='font-medium'>Featured</p>"
//   } else {
//     previewCard.classList.remove("bg-yellow-100")
//     previewCard.classList.add("bg-white")
//     dateEl.innerText = date
//   }
// })
