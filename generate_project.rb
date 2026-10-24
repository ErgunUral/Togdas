require 'xcodeproj'

root = File.expand_path(__dir__)
project = Xcodeproj::Project.new(File.join(root, 'Toqdas.xcodeproj'))
ios = project.new_target(:application, 'Toqdas', :ios, '16.0')
watch = project.new_target(:application, 'ToqdasWatch', :watchos, '9.0')

def sources(project, target, patterns)
  patterns.flat_map { |pattern| Dir.glob(File.join(__dir__, pattern)) }.sort.each do |file|
    reference = project.main_group.new_file(file.delete_prefix(__dir__ + '/'))
    target.source_build_phase.add_file_reference(reference)
  end
end

sources(project, ios, ['App/*.swift', 'Core/*.swift', 'Shared/*.swift'])
sources(project, watch, ['Watch/*.swift', 'Shared/*.swift', 'Core/*.swift'])

[[ios, 'com.toqdas.ios', 'App/Info.plist'], [watch, 'com.toqdas.ios.watchkitapp', 'Watch/Info.plist']].each do |target, bundle, plist|
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => bundle,
      'PRODUCT_NAME' => '$(TARGET_NAME)',
      'SWIFT_VERSION' => '5.0',
      'INFOPLIST_FILE' => plist,
      'MARKETING_VERSION' => '0.1.0',
      'CURRENT_PROJECT_VERSION' => '1',
      'CODE_SIGN_STYLE' => 'Automatic',
      'GENERATE_INFOPLIST_FILE' => 'NO',
      'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES'
    })
  end
end
ios.build_configurations.each { |c| c.build_settings['TARGETED_DEVICE_FAMILY'] = '1' }
watch.build_configurations.each do |c|
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '4'
  c.build_settings['SKIP_INSTALL'] = 'YES'
end
ios.add_dependency(watch)
embed = ios.new_copy_files_build_phase('Embed Watch Content')
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed.dst_subfolder_spec = '16'
embed.add_file_reference(watch.product_reference)
project.save

[ios, watch].each do |target|
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.set_launch_target(target)
  scheme.save_as(project.path, target.name, true)
end
puts project.path
