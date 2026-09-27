export default {
  mounted() {
    this.dirty = new Set()
    this.discardOnSave = new Map()
    this.status = () => {
      const status = this.el.querySelector("#unsaved-status")
      if (status) status.textContent = this.dirty.size
        ? "Unsaved changes — save each edited form before leaving."
        : "Saved. Add, move and delete apply immediately."
    }
    this.input = e => {
      const form = e.target.closest("form[phx-submit]")
      if (form) { this.dirty.add(form.id); this.status() }
    }
    this.leave = e => {
      if (this.dirty.size) { e.preventDefault(); e.returnValue = "" }
    }
    this.navigate = e => {
      if (e.target.closest("a[href], [data-mutates]") && this.dirty.size) {
        if (!window.confirm("You have unsaved changes. Continue without saving them?")) {
          e.preventDefault(); e.stopImmediatePropagation()
        } else { this.dirty.clear(); this.status() }
      }
    }
    this.submit = e => {
      this.discardOnSave.delete(e.target.id)
      const others = [...this.dirty].filter(id => id !== e.target.id)
      if (others.length) {
        const message = e.target.id === "duplicate-form"
          ? "Duplicate the saved plan and leave your unsaved changes behind?"
          : "Saving this form reloads the other forms and discards their unsaved changes. Continue?"
        if (!window.confirm(message)) {
          e.preventDefault(); e.stopImmediatePropagation()
          return
        }
        this.discardOnSave.set(e.target.id, others)
      }
    }
    this.el.addEventListener("input", this.input)
    this.el.addEventListener("change", this.input)
    this.el.addEventListener("click", this.navigate, true)
    this.el.addEventListener("submit", this.submit, true)
    window.addEventListener("beforeunload", this.leave)
    this.handleEvent("form-saved", ({id}) => {
      this.dirty.delete(id)
      for (const other of this.discardOnSave.get(id) || []) this.dirty.delete(other)
      this.discardOnSave.delete(id)
      const form = id && document.getElementById(id)
      if (form && (id === "catalog-form" || id.startsWith("add-exercise-") || id === "new-section-form" || id.startsWith("library-form-"))) form.reset()
      this.status()
    })
  },
  destroyed() {
    this.el.removeEventListener("input", this.input)
    this.el.removeEventListener("change", this.input)
    this.el.removeEventListener("click", this.navigate, true)
    this.el.removeEventListener("submit", this.submit, true)
    window.removeEventListener("beforeunload", this.leave)
  }
}
