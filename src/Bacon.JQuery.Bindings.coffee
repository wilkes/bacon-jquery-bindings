init = (Bacon, $) ->
  isChrome = navigator?.userAgent?.toLowerCase().indexOf("chrome") > -1
  id = (x) -> x
  nonEmpty = (x) -> x.length > 0
  fold = (xs, seed, f) ->
    for x in xs
      seed = f(seed, x)
    seed
  isModel = (obj) -> obj instanceof Bacon.Property

  globalModCount = 0
  idCounter = 1

  Model = Bacon.Model = Bacon.$.Model = (initValue) ->
    myModCount = 0
    modificationBus = new Bacon.Bus()
    syncBus = new Bacon.Bus()
    valueWithSource = modificationBus.scan(
      { initial: true }
      ({value}, {source, f}) -> {source, value: f(value)}
    ).changes().merge(syncBus).toProperty()
    model = valueWithSource.map(".value").skipDuplicates()
    model.id = idCounter++
    model.addSyncSource = (syncEvents) ->
      syncBus.plug(syncEvents.filter((e) ->
          if not e.modCount?
            e.modCount = ++globalModCount
          pass = e.modCount > myModCount
          myModCount = e.modCount
          pass
      ))
    model.apply = (source) -> 
      modificationBus.plug(source.map((f) -> {source, f}))
      valueWithSource.changes()
        .filter((change) -> change.source != source)
        .map((change) -> change.value)
    model.addSource = (source) -> model.apply(source.map((v) -> (->v)))
    model.modify = (f) -> model.apply(Bacon.once(f))
    model.set = (value) -> model.modify(-> value)
    model.syncEvents = -> valueWithSource.toEventStream()
    model.bind = (other) ->
      this.addSyncSource(other.syncEvents())
      other.addSyncSource(this.syncEvents())
    model.onValue()
    model.set(initValue) if (initValue?)
    model.lens = (lens) ->
      lens = Lens(lens)
      lensed = Model()
      valueLens = Lens.objectLens("value")
      this.addSyncSource(model.sampledBy(lensed.syncEvents(), (full, lensedSync) ->
        valueLens.set(lensedSync, lens.set(full, lensedSync.value))
      ))
      lensed.addSyncSource(this.syncEvents().map((e) -> 
        valueLens.set(e, lens.get(e.value))))
      lensed
    model

  Model.combine = (template) ->
    if typeof template != "object"
      Model(template)
    else if isModel(template)
      template
    else
      initValue = if template instanceof Array then [] else {}
      model = Model(initValue)
      for key, value of template
        lens = Lens.objectLens(key)
        lensedModel = model.lens(lens)
        lensedModel.bind(Model.combine(value))
      model

  Bacon.Binding = Bacon.$.Binding = ({ initValue, get, events, set}) ->
    inputs = events.map(get)
    if initValue?
      set(initValue)
    else
      initValue = get()
    binding = Bacon.Model(initValue)
    externalChanges = binding.addSource(inputs)
    externalChanges.assign(set)
    binding

  Lens = Bacon.Lens = Bacon.$.Lens = (lens) ->
    if typeof lens == "object"
      lens
    else
      Lens.objectLens(lens)

  Lens.id = Lens {
    get: (x) -> x
    set: (context, value) -> value
  }

  Lens.objectLens = (path) ->
    objectKeyLens = (key) -> 
      Lens {
        get: (x) -> x[key],
        set: (context, value) ->
          context = shallowCopy(context)
          context[key] = value
          context
      }
    keys = path.split(".").filter(nonEmpty)
    Lens.compose(keys.map(objectKeyLens)...)

  Lens.compose = (args...) -> 
    compose2 = (outer, inner) -> Lens {
      get: (x) -> inner.get(outer.get(x)),
      set: (context, value) ->
        innerContext = outer.get(context)
        newInnerContext = inner.set(innerContext, value)
        outer.set(context, newInnerContext)
    }
    fold(args, Lens.id, compose2)

  shallowCopy = (x) ->
    copy = if x instanceof Array
      []
    else
      {}
    for key, value of x
      copy[key] = value
    copy

  $.fn.asEventStream = Bacon.$.asEventStream
  Bacon.$.textFieldValue = (element, initValue) ->
    nonEmpty = (x) -> x.length > 0
    get = -> element.val()
    autofillPoller = ->
      if element.attr("type") is "password"
        Bacon.interval 100
      else if isChrome
        Bacon.interval(100).take(20).map(get).filter(nonEmpty).take 1
      else
        Bacon.never()
    events = element.asEventStream("keyup input")
      .merge(element.asEventStream("cut paste").delay(1))
      .merge(autofillPoller())

    Bacon.Binding {
      initValue,
      get,
      events,
      set: (value) -> element.val(value)
    }
  Bacon.$.checkBoxValue = (element, initValue) ->
    Bacon.Binding {
      initValue,
      get: -> !!element.attr("checked"),
      events: element.asEventStream("change"),
      set: (value) -> element.attr "checked", value
    }
  
  Bacon.$.selectValue = (element, initValue) ->
    Bacon.Binding {
      initValue,
      get: -> element.val(),
      events: element.asEventStream("change"),
      set: (value) -> element.val value
    }

  Bacon.$.radioGroupValue = (radios, initValue) ->
    Bacon.Binding {
      initValue,
      get: -> radios.filter(":checked").first().val(),
      events: radios.asEventStream("change"),
      set: (value) ->
        radios.each (i, elem) ->
          if elem.value is value
            $(elem).attr "checked", true 
          else
            $(elem).removeAttr "checked"
    }

  Bacon.$.checkBoxGroupValue = (checkBoxes, initValue) ->
    Bacon.Binding {
      initValue,
      get: -> selectedValues = ->
        checkBoxes.filter(":checked").map((i, elem) -> $(elem).val()).toArray()
      events: checkBoxes.asEventStream("click,change"),
      set: (value) ->
        checkBoxes.each (i, elem) ->
          $(elem).attr "checked", value.indexOf($(elem).val()) >= 0
    }

  Bacon.$

if module?
  Bacon = require("baconjs")
  $ = require("jquery")
  module.exports = init(Bacon, $)
else
  if typeof require is 'function'
    define 'bacon-jquery-bindings', ["bacon", "jquery"], init
  else
    init(this.Bacon, this.$)
