gulp        = require 'gulp'
gp          = do require 'gulp-load-plugins'
inline      = require 'rework-inline'
tinylr      = require 'tiny-lr'
express     = require 'express'
marked      = require 'marked'
path        = require 'path'
es          = require 'event-stream'
pak         = require './package.json'
connectlr   = require 'connect-livereload'

app         = express()
server      = tinylr()

port        = 8000
lr_port     = 35729

dest        = 'dist/'
src         = 'src/'
assets      = 'assets/'


paths=
  vendor_styl:        'bower_components/bootstrap-stylus/stylus/'
  vendor_js:          [
    'bower_components/jquery/dist/jquery.js'
    'bower_components/bootstrap/dist/js/bootstrap.js'
  ]
  vendor_fonts:       'bower_components/bootstrap/dist/fonts/*'

  src_stylesheets:    src + assets + 'stylesheets/*.styl'
  src_scripts:        src + assets + 'scripts/'
  src_coffee:         this.src_scripts + '*.coffee'
  src_js:             this.src_scripts + '*.js'
  src_templates:      src + '*.jade'

  dest_stylesheets:   dest + assets + 'stylesheets'
  dest_scripts:       dest + assets + 'scripts'
  dest_fonts:         dest + assets + 'fonts'

styles = ->
  gulp.src paths.src_stylesheets
    .pipe gp.plumber()
    .pipe gp.stylus include: paths.vendor_styl
    .pipe gp.autoprefixer "> 1%"
    .pipe gp.concat pak.name + '.css'

gulp.task 'copy-fonts', ->
  gulp.src paths.vendor_fonts
    .pipe gulp.dest paths.dest_fonts


gulp.task 'css', ['copy-fonts'], ->
  gp.util.log 'Performing css task'
  styles()
    .pipe gulp.dest paths.dest_stylesheets
    .pipe gp.livereload(server)

gulp.task 'js', ->
  gp.util.log 'Performing js task'
  es.merge(
      gulp.src(paths.vendor_js),
      gulp.src(paths.src_coffee),
      gulp.src(paths.src_js))
    .pipe gp.concat pak.name + '.min.js'
    .pipe gulp.dest paths.dest_scripts
    .pipe gp.livereload server


gulp.task 'templates', ->
  gp.util.log 'Performing templates task'
  gulp.src paths.src_templates
    .pipe gp.plumber()
    .pipe gp.jade pretty:true
    .pipe gulp.dest dest
    .pipe gp.livereload server

gulp.task 'express', ->
  app.use connectlr port: lr_port
  app.use express.static path.resolve dest
  app.listen port
  gp.util.log 'Listening on port: ' + port
  return

gulp.task 'watch', ->
  server.listen lr_port, (err)->
    if err
      return console.log err
    else
      gulp.watch paths.src_stylesheets, ['css-production']
      gulp.watch paths.src_js, ['js']
      gulp.watch paths.src_coffee, ['js'] 
      gulp.watch paths.src_templates, ['templates']
      return

gulp.task 'default', ['js', 'css-production', 'templates', 'express', 'watch']

# Production tasks

gulp.task 'css-production', ['templates-production'], ->
  styles()
    .pipe gp.uncss html: [dest + 'index.html']
    .pipe gp.csso()
    .pipe gp.rename suffix: '.min'
    .pipe gulp.dest paths.dest_stylesheets

gulp.task 'templates-production', ->
  gp.util.log 'Performing templates task'
  gulp.src paths.src_templates
    .pipe gp.plumber()
    .pipe gp.jade()
    .pipe gulp.dest dest

gulp.task 'production', ['css-production', 'templates-production']

gulp.task 'clean', ->
  gulp.src dest, read: false
    .pipe gp.rimraf()