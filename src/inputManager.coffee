
class InputManager extends Plugin

  @className: 'InputManager'

  opts:
    pasteImage: false

  constructor: (args...) ->
    super args...
    @editor = @widget
    @opts.pasteImage = 'inline' if @opts.pasteImage and typeof @opts.pasteImage != 'string'

    # handlers which will be called when specific key is pressed in specific node
    @_keystrokeHandlers = {}

    @_shortcuts = {}

  _modifierKeys: [16, 17, 18, 91, 93, 224]

  _arrowKeys: [37..40]

  _init: ->

    @_pasteArea = $('<div/>')
      .css({
        width: '1px',
        height: '1px',
        overflow: 'hidden',
        position: 'fixed',
        right: '0',
        bottom: '100px'
      })
      .attr({
        tabIndex: '-1',
        contentEditable: true
      })
      .addClass('simditor-paste-area')
      .appendTo(@editor.el)

    @_cleanPasteArea = $('<textarea/>')
      .css({
        width: '1px',
        height: '1px',
        overflow: 'hidden',
        position: 'fixed',
        right: '0',
        bottom: '101px'
      })
      .attr({
        tabIndex: '-1'
      })
      .addClass('simditor-clean-paste-area')
      .appendTo(@editor.el)

    @editor.on 'valuechanged', =>
      # make sure each code block and table has siblings
      @editor.body.find('hr, pre, .simditor-table').each (i, el) =>
        $el = $(el)
        if ($el.parent().is('blockquote') or $el.parent()[0] == @editor.body[0])
          formatted = false

          if $el.next().length == 0
            $('<p/>').append(@editor.util.phBr)
              .insertAfter($el)
            formatted = true

          if $el.prev().length == 0
            $('<p/>').append(@editor.util.phBr)
              .insertBefore($el)
            formatted = true

          if formatted
            setTimeout =>
              @editor.trigger 'valuechanged'
            , 10

      @editor.body.find('pre:empty').append(@editor.util.phBr)


    @editor.body.on('keydown', $.proxy(@_onKeyDown, @))
      .on('keypress', $.proxy(@_onKeyPress, @))
      .on('keyup', $.proxy(@_onKeyUp, @))
      .on('mouseup', $.proxy(@_onMouseUp, @))
      .on('focus', $.proxy(@_onFocus, @))
      .on('blur', $.proxy(@_onBlur, @))
      .on('paste', $.proxy(@_onPaste, @))
      .on('drop', $.proxy(@_onDrop, @))

    # fix firefox cmd+left/right bug
    if @editor.util.browser.firefox
      @addShortcut 'cmd+37', (e) =>
        e.preventDefault()
        @editor.selection.sel.modify('move', 'backward', 'lineboundary')
        false
      @addShortcut 'cmd+39', (e) =>
        e.preventDefault()
        @editor.selection.sel.modify('move', 'forward', 'lineboundary')
        false

    # meta + enter: submit form
    submitKey = if @editor.util.os.mac then 'cmd+13' else 'ctrl+13'
    @addShortcut submitKey, (e) =>
      @editor.el.closest('form')
        .find('button:submit')
        .click()
      false

    if @editor.textarea.attr 'autofocus'
      setTimeout =>
        @editor.focus()
      , 0


  _onFocus: (e) ->
    @editor.el.addClass('focus')
      .removeClass('error')
    @focused = true
    @lastCaretPosition = null

    #@editor.body.find('.selected').removeClass('selected')

    setTimeout =>
      @editor.triggerHandler 'focus'
      #@editor.trigger 'selectionchanged'
    , 0

  _onBlur: (e) ->
    @editor.el.removeClass 'focus'
    @editor.sync()
    @focused = false
    @lastCaretPosition = @editor.undoManager.currentState()?.caret

    @editor.triggerHandler 'blur'

  _onMouseUp: (e) ->
    setTimeout =>
      @editor.trigger 'selectionchanged'
      @editor.undoManager.update()
    , 0

  _onKeyDown: (e) ->
    if @editor.triggerHandler(e) == false
      return false

    # handle predefined shortcuts
    shortcutKey = @editor.util.getShortcutKey e
    if @_shortcuts[shortcutKey]
      return @_shortcuts[shortcutKey].call(this, e)

    # Check the condictional handlers
    if e.which of @_keystrokeHandlers
      result = @_keystrokeHandlers[e.which]['*']?(e)
      if result
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
        return false

      @editor.util.traverseUp (node) =>
        return unless node.nodeType == 1
        handler = @_keystrokeHandlers[e.which]?[node.tagName.toLowerCase()]
        result = handler?(e, $(node))

        # different result means:
        # 1. true, has do everythings, stop browser default action and traverseUp
        # 2. false, stop traverseUp
        # 3. undefined, continue traverseUp
        false if result == true or result == false
      if result
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
        return false

    if e.which in @_modifierKeys or e.which in @_arrowKeys
      return

    metaKey = @editor.util.metaKey e
    $blockEl = @editor.util.closestBlockEl()

    # paste shortcut
    return if metaKey and e.which == 86

    if @editor.util.browser.webkit and e.which == 8 and @editor.selection.rangeAtStartOf $blockEl
      # fix the span bug in webkit browsers
      setTimeout =>
        $newBlockEl = @editor.util.closestBlockEl()
        @editor.selection.save()
        @editor.formatter.cleanNode $newBlockEl, true
        @editor.selection.restore()
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
      , 10
      @typing = true
    else if @_typing
      clearTimeout @_typing if @_typing != true
      @_typing = setTimeout =>
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
        @_typing = false
      , 200
    else
      setTimeout =>
        @editor.trigger 'valuechanged'
        @editor.trigger 'selectionchanged'
      , 10
      @_typing = true

    null

  _onKeyPress: (e) ->
    if @editor.triggerHandler(e) == false
      return false

  _onKeyUp: (e) ->
    if @editor.triggerHandler(e) == false
      return false

    if e.which in @_arrowKeys
      @editor.trigger 'selectionchanged'
      @editor.undoManager.update()
      return

    if e.which == 8 and @editor.util.isEmptyNode(@editor.body)
      @editor.body.empty()
      p = $('<p/>').append(@editor.util.phBr)
        .appendTo(@editor.body)
      @editor.selection.setRangeAtStartOf p
      return

  _onPaste: (e) ->
    if @editor.triggerHandler(e) == false
      return false

    range = @editor.selection.deleteRangeContents()
    range.collapse(true) unless range.collapsed
    $blockEl = @editor.util.closestBlockEl()
    cleanPaste = $blockEl.is 'pre, table'

    if e.originalEvent.clipboardData && e.originalEvent.clipboardData.items && e.originalEvent.clipboardData.items.length > 0
      pasteItem = e.originalEvent.clipboardData.items[0]

      # paste file in chrome
      if /^image\//.test(pasteItem.type) and !cleanPaste
        imageFile = pasteItem.getAsFile()
        return unless imageFile? and @opts.pasteImage

        unless imageFile.name
          imageFile.name = "Clipboard Image.png"

        uploadOpt = {}
        uploadOpt[@opts.pasteImage] = true
        @editor.uploader?.upload(imageFile, uploadOpt)
        return false

    @editor.selection.save range

    if cleanPaste
      @_cleanPasteArea.focus()

      # firefox cannot set focus on textarea before pasting
      if @editor.util.browser.firefox
        e.preventDefault()
        @_cleanPasteArea.val e.originalEvent.clipboardData.getData('text/plain')

      # IE10 cannot set focus on textarea or editable div before pasting
      else if @editor.util.browser.msie and @editor.util.browser.version == 10
        e.preventDefault()
        @_cleanPasteArea.val window.clipboardData.getData('Text')
    else
      @_pasteArea.focus()

      # IE10 cannot set focus on textarea or editable div before pasting
      if @editor.util.browser.msie and @editor.util.browser.version == 10
        e.preventDefault()
        @_pasteArea.html window.clipboardData.getData('Text')

    setTimeout =>
      if @_pasteArea.is(':empty') and !@_cleanPasteArea.val()
        pasteContent = null
      else if cleanPaste
        pasteContent = @_cleanPasteArea.val()
      else
        pasteContent = $('<div/>').append(@_pasteArea.contents())
        @editor.formatter.format pasteContent
        @editor.formatter.decorate pasteContent
        @editor.formatter.beautify pasteContent.children()
        pasteContent = pasteContent.contents()

      @_pasteArea.empty()
      @_cleanPasteArea.val('')
      range = @editor.selection.restore()

      if @editor.triggerHandler('pasting', [pasteContent]) == false
        return

      if !pasteContent
        return
      else if cleanPaste
        if $blockEl.is('table')
          lines = pasteContent.split('\n')
          lastLine = lines.pop()
          for line in lines
            @editor.selection.insertNode document.createTextNode(line)
            @editor.selection.insertNode $('<br/>')
          @editor.selection.insertNode document.createTextNode(lastLine)
        else
          pasteContent = $('<div/>').text(pasteContent)
          @editor.selection.insertNode($(node)[0], range) for node in pasteContent.contents()
      else if $blockEl.is @editor.body
        @editor.selection.insertNode(node, range) for node in pasteContent
      else if pasteContent.length < 1
        return
      else if pasteContent.length == 1
        if pasteContent.is('p')
          children = pasteContent.contents()

          if children.length == 1 and children.is('img')
            $img = children

            # paste image in firefox and IE 11
            if /^data:image/.test($img.attr('src'))
              return unless @opts.pasteImage
              blob = @editor.util.dataURLtoBlob $img.attr( "src" )
              blob.name = "Clipboard Image.png"

              uploadOpt = {}
              uploadOpt[@opts.pasteImage] = true
              @editor.uploader?.upload(blob, uploadOpt)
              return

            # cannot paste image in safari
            else if $img.is('img[src^="webkit-fake-url://"]')
              return
          else
            @editor.selection.insertNode(node, range) for node in children

        else if $blockEl.is('p') and @editor.util.isEmptyNode $blockEl
          $blockEl.replaceWith pasteContent
          @editor.selection.setRangeAtEndOf(pasteContent, range)
        else if pasteContent.is('ul, ol')
          if pasteContent.find('li').length == 1
            pasteContent = $('<div/>').text(pasteContent.text())
            @editor.selection.insertNode($(node)[0], range) for node in pasteContent.contents()
          else if $blockEl.is 'li'
            $blockEl.parent().after pasteContent
            @editor.selection.setRangeAtEndOf(pasteContent, range)
        else
          $blockEl.after pasteContent
          @editor.selection.setRangeAtEndOf(pasteContent, range)
      else
        $blockEl = $blockEl.parent() if $blockEl.is 'li'

        if @editor.selection.rangeAtStartOf($blockEl, range)
          insertPosition = 'before'
        else if @editor.selection.rangeAtEndOf($blockEl, range)
          insertPosition = 'after'
        else
          @editor.selection.breakBlockEl($blockEl, range)
          insertPosition = 'before'

        $blockEl[insertPosition](pasteContent)
        @editor.selection.setRangeAtEndOf(pasteContent.last(), range)

      @editor.trigger 'valuechanged'
      @editor.trigger 'selectionchanged'
    , 10

  _onDrop: (e) ->
    if @editor.triggerHandler(e) == false
      return false

    setTimeout =>
      @editor.trigger 'valuechanged'
      @editor.trigger 'selectionchanged'
    , 0


  addKeystrokeHandler: (key, node, handler) ->
    @_keystrokeHandlers[key] = {} unless @_keystrokeHandlers[key]
    @_keystrokeHandlers[key][node] = handler


  addShortcut: (keys, handler) ->
    @_shortcuts[keys] = $.proxy(handler, this)
