require 'json'
project = JSON.parse(IO.popen(['plutil', '-convert', 'json', '-o', '-', 'ScriptMakerMac.xcodeproj/project.pbxproj'], &:read))
objects = project.fetch('objects')
references = {}
walk = nil
walk = lambda do |id, directory|
  object = objects.fetch(id)
  path = object['path']
  current = path && object['sourceTree'] == '<group>' ? File.join(directory, path) : directory
  if object['isa'] == 'PBXGroup'
    object.fetch('children', []).each { |child| walk.call(child, current) }
  elsif path&.end_with?('.swift')
    references[id] = current.sub(%r{\A\./}, '')
  end
end
walk.call(objects.fetch(project.fetch('rootObject')).fetch('mainGroup'), '.')
compiled = objects.values.select { |o| o['isa'] == 'PBXSourcesBuildPhase' }
  .flat_map { |o| o.fetch('files') }
  .map { |id| references[objects.fetch(id)['fileRef']] }.compact
expected = Dir['Sources/**/*.swift', 'Tests/**/*.swift']
missing = (expected - compiled) + compiled.reject { |file| File.file?(file) }
abort "Invalid Swift source membership: #{missing.join(', ')}" unless missing.empty?
