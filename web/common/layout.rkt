#lang at-exp racket/base

(require scribble/html racket/dict (for-syntax racket/base syntax/name syntax/parse)
         "utils.rkt" "resources.rkt")

(define-for-syntax (process-contents who layouter stx xs)
  (let loop ([xs xs] [kws '()] [id? #f])
    (syntax-case xs ()
      [(k v . xs) (keyword? (syntax-e #'k))
       (loop #'xs (list* #'v #'k kws) (or id? (eq? '#:id (syntax-e #'k))))]
      [_ (with-syntax ([layouter layouter]
                       [(x ...) (reverse kws)]
                       [(id ...)
                        (if id?
                          '()
                          (let ([name (or (syntax-property stx 'inferred-name)
                                          (syntax-local-name))])
                            (if name (list '#:id `',name) '())))]
                       ;; delay body, allow definitions
                       [body #`(λ () (begin/text #,@xs))])
           #'(layouter id ... x ... body))])))

(define (get-path who id file sfx dir)
  (define file*
    (or file
        (let ([f (and id (symbol->string (force id)))])
          (cond [(and f (regexp-match #rx"[.]" f)) f]
                [(and f sfx)
                 (string-append f (regexp-replace #rx"^[.]?" sfx "."))]
                [else (error who "missing `#:file', or `#:id'~a"
                             (if sfx "" " and `#:suffix'"))]))))
  (if dir (web-path dir file*) file*))

;; The following are not intended for direct use, see
;; `define+provide-context' below (it could be used with #f for the
;; directory if this ever gets used for a flat single directory web
;; page.)

;; for plain text files
(define-syntax (plain stx)
  (syntax-case stx () [(_ . xs) (process-contents 'plain #'plain* stx #'xs)]))
(define (plain* #:id [id #f] #:suffix [suffix #f]
                #:dir [dir #f] #:file [file #f]
                #:referrer [referrer values]
                #:newline [newline? #t]
                content)
  (resource/referrer (get-path 'plain id file suffix dir)
                     (file-writer output (list content (and newline? "\n")))
                     referrer))

;; page layout function
(define-syntax (page stx)
  (syntax-case stx () [(_ . xs) (process-contents 'page #'page* stx #'xs)]))
(define (page* #:id [id #f] #:dir [dir #f] #:file [file #f]
               ;; if this is true, return only the html -- don't create
               ;; a resource -- therefore no file is made, and no links
               ;; to it can be made (useful only for stub templates)
               #:html-only [html-only? #f]
               #:title [label (if id
                                (let* ([id (->string (force id))]
                                       [id (regexp-replace #rx"^.*/" id "")]
                                       [id (regexp-replace #rx"-" id " ")])
                                  (string-titlecase id))
                                (error 'page "missing `#:id' or `#:title'"))]
               #:link-title [linktitle label]
               #:window-title [wintitle @list{Racket: @label}]
               ;; can be #f (default), 'full: full page (and no div),
               ;; otherwise, a css width
               #:width [width #f]
               #:description [description #f] ; for a meta tag
               #:extra-headers [extra-headers #f]
               #:extra-body-attrs [body-attrs #f]
               #:resources resources0 ; see below
               #:referrer [referrer
                           (λ (url . more)
                             (a href: url (if (null? more) linktitle more)))]
               ;; will be used instead of `this' to determine navbar highlights
               #:part-of [part-of #f]
               content0)
  (define (page)
    (define desc
      (and description (meta name: 'description content: description)))
    (define resources (force resources0))
    (define header
      (let ([headers (resources 'headers)]
            [extras  (if (and extra-headers desc)
                       (list desc "\n" extra-headers)
                       (or desc extra-headers))])
        (if extras (list headers "\n" extras) headers)))
    (define navbar ((resources 'make-navbar) (or part-of this)))
    (define content
      (list navbar "\n"
            (case width
              [(full) content0]
              [(#f) (div class: 'bodycontent content0)]
              [else (div class: 'bodycontent style: @list{width: @|width|@";"}
                      content0)])
            (resources 'postamble)))
    @list{@resources['preamble]
          @html{@||
                @head{@||
                      @title{@wintitle}
                      @header
                      @||}
                @(if body-attrs
                   (apply body `(,@body-attrs ,content))
                   (body content))}
          @||})
  (define this (and (not html-only?)
                    (resource/referrer (get-path 'page id file "html" dir)
                                       (file-writer output-xml page)
                                       referrer)))
  (when this (pages->part-of this (or part-of this)))
  (or this page))

;; maps pages to their parts, so symbolic values can be used to determine it
(define pages->part-of
  (let ([t (make-hasheq)])
    (case-lambda [(page) (hash-ref t page page)]
                 [(page part-of) (hash-set! t page part-of)])))

(provide set-navbar!)
(define-syntax-rule (set-navbar! pages top help)
  (if (unbox navbar-info)
    ;; since generation is delayed, it won't make sense to change the navbar
    (error 'set-navbar! "called twice")
    (set-box! navbar-info (list (lazy pages) (lazy top) (lazy help)))))

(define navbar-info (box #f))
(define ((navbar-maker logo) this)
  (define (icon name) @i[class: name]{})
  (define (row . content) (apply div class: "row" content))
  
  (define download-promise (dict-ref (force (first (unbox navbar-info))) 'download))
  (define main-promise (force (second (unbox navbar-info))))
  
  @div[class: "navbar" gumby-fixed: "top" id: "nav1"]{
  @row{
   @a[class: "toggle" gumby-trigger: "#nav1 > .row > ul" href: "#"]{
     @icon{icon-menu}}
   @a[class: "five columns logo" href: (url-of main-promise)]{
     @img[class: "logo" src: logo]}
   @ul[class: "five columns"]{
     @li{@a[href: "http://pkg.racket-lang.org"]{Packages}}
     @li{@a[href: "http://docs.racket-lang.org"]{Documentation}}
     @li{@a[href: "http://blog.racket-lang.org"]{Blog}}
     @li{@div[class: "medium metro info btn icon-left entypo icon-install"]{
       @download-promise}}}}})

(define html-preamble
  @list{
    @doctype['html]
    @; paulirish.com/2008/conditional-stylesheets-vs-css-hacks-answer-neither/
    @comment{[if lt IE 7]> <html class="no-js ie6 oldie" lang="en"> <![endif]}
    @comment{[if IE 7]>    <html class="no-js ie7 oldie" lang="en"> <![endif]}
    @comment{[if IE 8]>    <html class="no-js ie8 oldie" lang="en"> <![endif]}
    @comment{[if IE 9]>    <html class="no-js ie9" lang="en"> <![endif]}
    @comment{[if gt IE 9]><!--> <html class="no-js" lang="en" @;
             itemscope itemtype="http://schema.org/Product"> <!--<![endif]}
    })

(define (make-html-postamble resources)
  @list{
    @||
    @; Grab Google CDN's jQuery, with a protocol relative URL;
    @;   fall back to local if offline
    @script[src: '("http://ajax.googleapis.com/"
                   "ajax/libs/jquery/1.9.1/jquery.min.js")]
    @script/inline{
      window.jQuery || document.write(@;
        '<script src="/js/libs/jquery-1.9.1.min.js"><\/script>')}
    @script[src: (resources "gumby.min.js")]
    @script[src: (resources "plugins.js")]
    @script[src: (resources "main.js")]
    @||
    })

(define (html-icon-headers icon)
  @; Place favicon.ico and apple-touch-icon.png in the root
  @;   directory: mathiasbynens.be/notes/touch-icons
  @list{@link[rel: "icon"          href: icon type: "image/ico"]
        @link[rel: "shortcut icon" href: icon type: "image/x-icon"]})

(define (html-headers resources favicon)
  (define style (resources 'style-path))
  @list{
    @meta[name: "generator" content: "Racket"]
    @meta[http-equiv: "Content-Type" content: "text/html; charset=utf-8"]
    @meta[charset: "utf-8"]
    @; Use the .htaccess and remove this line to avoid edge case issues.
    @; More info: h5bp.com/b/378
    @meta[http-equiv: "X-UA-Compatible" content: "IE=edge,chrome=1"]
    @favicon
    @; Mobile viewport optimized: j.mp/bplateviewport
    @meta[name: "viewport"
          content: "width=device-width, initial-scale=1.0, maximum-scale=1"]
    @; CSS: implied media=all
    @; CSS concatenated and minified via ant build script
    @; @link[rel: "stylesheet" href="css/minified.css"]
    @; CSS imports non-minified for staging, minify before moving to
    @;   production
    @link[rel: "stylesheet" href: (resources "gumby.css")]
    @;@link[rel: "stylesheet" href: (resources "style.css")]
    @; TODO: Modify `racket-style' definition (and what it depends on)
    @;   in "resources.rkt", possibly do something similar with the new files
    @link[rel: "stylesheet" type: "text/css" href: style title: "default"]
    @; TODO: Edit the `more.css' definition in www/index.rkt
    @; More ideas for your <head> here: h5bp.com/d/head-Tips
    @; All JavaScript at the bottom, except for Modernizr / Respond.
    @; Modernizr enables HTML5 elements & feature detects; Respond is
    @;   a polyfill for min/max-width CSS3 Media Queries
    @; For optimal performance, use a custom Modernizr build:
    @;   www.modernizr.com/download/
    @script[src: (resources "modernizr-2.6.2.min.js")]
    })

(define (make-resources files)
  (define (resources what)
    (case what
      ;; composite resources
      [(preamble)     html-preamble] ; not really a resource, since it's static
      [(postamble)    html-postamble]
      [(headers)      headers]
      [(make-navbar)  make-navbar] ; page -> navbar
      [(icon-headers) icon-headers]
      ;; aliases for specific resource files
      [(style-path) (resources "plt.css")]
      [(logo-path)  (resources "logo.png")]
      [(icon-path)  (resources "plticon.ico")]
      ;; get a resource file path
      [else (cond [(assoc what files)
                   ;; delay the `url-of' until we're in the rendering context
                   => (λ(f) (λ() (url-of (cadr f))))]
                  [else (error 'resource "unknown resource: ~e" what)])]))
  (define icon-headers   (html-icon-headers (resources 'icon-path)))
  (define headers        (html-headers resources icon-headers))
  (define make-navbar    (navbar-maker (resources 'logo-path)))
  (define html-postamble (make-html-postamble resources))
  resources)

;; `define+provide-context' should be used in each toplevel directory (= each
;; site) to have its own resources (and possibly other customizations).
(provide define+provide-context define-context)
(define-for-syntax (make-define+provide-context stx provide?)
  (syntax-parse stx
    [(_ (~or (~optional dir:expr)
             (~optional (~seq #:resources resources))
             (~optional (~seq #:robots robots) #:defaults ([robots #'#t]))
             (~optional (~seq #:htaccess htaccess) #:defaults ([htaccess #'#t])))
        ...)
     (unless (attribute dir)
       (raise-syntax-error 'define-context "missing <dir>"))
     (with-syntax ([page-id      (datum->syntax stx 'page)]
                   [plain-id     (datum->syntax stx 'plain)]
                   [copyfile-id  (datum->syntax stx 'copyfile)]
                   [symlink-id   (datum->syntax stx 'symlink)]
                   [resources-id (datum->syntax stx 'the-resources)])
       (with-syntax ([provides   (if provide?
                                   #'(provide page-id plain-id copyfile-id
                                              symlink-id resources-id)
                                   #'(begin))]
                     [resources
                      (or (attribute resources)
                          #'(make-resources
                             (make-resource-files
                              (λ (id . content)
                                (page* #:id id #:dir dir
                                       #:resources (lazy resources-id)
                                       content))
                              dir robots htaccess)))])
         #'(begin
             (define resources-id resources)
             (define-syntax-rule (page-id . xs)
               (page #:resources resources-id #:dir dir . xs))
             (define-syntax-rule (plain-id . xs)
               (plain #:dir dir . xs))
             (define copyfile-id
               (case-lambda [(s)   (copyfile-resource s #:dir dir)]
                            [(s t) (copyfile-resource s t #:dir dir)]))
             (define symlink-id
               (case-lambda [(s)   (symlink-resource s #:dir dir)]
                            [(s t) (symlink-resource s t #:dir dir)]))
             provides)))]))
(define-syntax (define+provide-context stx)
  (make-define+provide-context stx #t))
(define-syntax (define-context stx)
  (make-define+provide-context stx #f))
