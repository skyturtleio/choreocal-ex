import test from "node:test"
import assert from "node:assert/strict"
import UnsavedForms from "../../assets/js/unsaved_forms.mjs"

function mount(confirm) {
  globalThis.window = {confirm, addEventListener() {}, removeEventListener() {}}
  globalThis.document = {getElementById() { return null }}
  const status = {textContent: ""}
  const hook = {
    el: {querySelector() {return status}, addEventListener() {}, removeEventListener() {}},
    handleEvent(_, callback) {this.saved = callback}
  }
  UnsavedForms.mounted.call(hook)
  return hook
}
function submit(id) {
  return {target: {id}, prevented: false, stopped: false,
    preventDefault() {this.prevented = true}, stopImmediatePropagation() {this.stopped = true}}
}

test("both cross-form directions cancel without clearing drafts or reaching LiveView", () => {
  for (const [draft, submitted] of [["class-form", "add-exercise-1"], ["exercise-form-1", "class-form"]]) {
    const hook = mount(message => {assert.match(message, /reloads.*discards/); return false})
    hook.dirty.add(draft)
    const event = submit(submitted)
    hook.submit(event)
    assert.equal(event.prevented, true)
    assert.equal(event.stopped, true)
    assert.deepEqual([...hook.dirty], [draft])
  }
})
test("accepted discard stays dirty on failure and clears only with successful save", () => {
  const hook = mount(() => true)
  hook.dirty.add("class-form"); hook.dirty.add("add-exercise-1")
  const event = submit("add-exercise-1")
  hook.submit(event)
  assert.equal(event.prevented, false)
  assert.equal(hook.dirty.size, 2)
  hook.saved({id: "add-exercise-1"})
  assert.equal(hook.dirty.size, 0)
})
test("saving the only dirty form does not prompt", () => {
  const hook = mount(() => {throw new Error("unnecessary confirmation")})
  hook.dirty.add("class-form")
  hook.submit(submit("class-form"))
  hook.saved({id: "class-form"})
  assert.equal(hook.dirty.size, 0)
})
