require "imsticker/version"
require 'zip'
require 'open-uri'
require 'json'
require 'image_resizer'
require 'pathname'

module Imsticker

  def self.generate
    # check if info.json exists
    if File.exist?("info.json") == false
      raise "Where is your info.json file?"
    end
    if Dir.exist?('stickers') == false
      raise "Cannot find `stickers` directory in current directory."
    end

    # check if have downloaded template
    # if yes, check version. if new version exists, download new template
    # if no, download template
    tmp_dir = File.join(Dir.home, ".imsticker")
    if Dir.exist?(tmp_dir) == false
      Dir.mkdir(tmp_dir)
    end

    template_dir = File.join(tmp_dir, 'template')
    version_file = File.join(template_dir, 'version')
    if File.exist?(version_file) == false
      download_template(tmp_dir, template_dir)
    else
      downloaded_version = File.read(version_file)
      puts "Current template version: #{downloaded_version}"
      recent_version = downloaded_version
      open('https://raw.githubusercontent.com/nicnocquee/iOStickersTemplate/master/version') {|f|
        recent_version = f.read
      }
      puts "Online version #{recent_version}"
      if downloaded_version != recent_version
        puts "New template version available. Downloading ..."
        download_template(tmp_dir, template_dir)
      end
    end

    # copy the template to temp directory
    proj_tmp_dir = Dir.mktmpdir
    puts "Creating temp directory to #{proj_tmp_dir} and copy the templates ..."
    FileUtils.cp_r template_dir, proj_tmp_dir
    proj_tmp_dir = File.join(proj_tmp_dir, 'template')

    # read info file
    info = JSON.parse(File.read('./info.json'))
    info['name'] = "#{info['name'].split.map(&:capitalize)*' '}"

    # list files in stickers folder. single file = single sticker image, a folder = sticker sequence
    supported_exts = ['png', 'apng', 'gif', 'jpeg', 'jpg']
    supported_files = File.join(File.join('.', 'stickers'), "*.{#{supported_exts.join(',')}}")

    sticker_target_directory = File.join(File.join(File.join(proj_tmp_dir, 'StickerPackExtension'), 'Stickers.xcstickers'), "Sticker Pack.stickerpack")
    puts sticker_target_directory
    sticker_contents_json = {
      'info' => {
        'version' => 1,
        'author' => 'xcode'
      },
      'properties' => {
        'filename' => ''
      }
    }
    sticker_sequence_contents_json = {
      'info' => {
        'version' => 1,
        'author' => 'xcode'
      },
      'properties' => {
        "duration" => 15,
        "duration-type" => "fps",
        "repetitions" => 0
      },
      'frames' => []
    }
    stickers_contents_json_file = File.join(sticker_target_directory, 'Contents.json')
    stickers_contents_json = JSON.parse(File.read(stickers_contents_json_file))

    # create a directory in Sticker Pack.stickerpack directory for each of the stickers. e.g., file_name.sticker, file_name.stickersequence
    Dir.entries('stickers').select {|entry|
      if entry != '.' && entry != '..'
        file = File.join('stickers', entry)
        ext_with_period = File.extname(file)
        file_name_without_ext = File.basename(file, ext_with_period)
        ext = ext_with_period.downcase.strip.split('.').last
        sticker_entry = ''
        # if single sticker, write Contents.json in it with content following Contents-sticker.json, copy the image file to the directory.
        if supported_exts.include?(ext)
            puts "Single sticker: #{entry}"
            sticker_entry = "#{file_name_without_ext}.sticker"
            sticker_dir = File.join(sticker_target_directory, sticker_entry)
            Dir.mkdir(sticker_dir)
            FileUtils.cp(file, File.join(sticker_dir, entry))
            sticker_contents_json['properties']['filename'] = entry
            json = JSON.generate(sticker_contents_json)
            File.open(File.join(sticker_dir, 'Contents.json'), "w") {|f|
              f.write(json)
            }
        end

        # if stickersequence, write Contents.json in it with content following Contents-stickersequence.json, copy the images files to the dir.
        if File.directory?(file)
          puts "Sticker Sequence: #{entry}"
          sticker_entry = "#{file_name_without_ext}.stickersequence"
          sticker_dir = File.join(sticker_target_directory, sticker_entry)
          Dir.mkdir(sticker_dir)
          Dir.entries(file).sort_by {|f| File.basename(f)}.select {|f|
            if f != '.' && f != '..'
              FileUtils.cp(File.join(file, f), File.join(sticker_dir, f))
              sticker_sequence_contents_json['frames'].push({
                'filename' => f
              })
            end
          }
          json = JSON.generate(sticker_sequence_contents_json)
          File.open(File.join(sticker_dir, 'Contents.json'), "w") {|f|
            f.write(json)
          }
        end

        # add `stickers` key in Sticker Pack.stickerpack/Contents.json with value an array of dictionaries: { "filename": "stickername.sticker" }
        if sticker_entry != ''
          stickers_contents_json['stickers'].push({
              'filename' => sticker_entry
          })
        end
      end

      # write Sticker Pack.stickerpack/Contents.json
      json = JSON.generate(stickers_contents_json)
      File.open(stickers_contents_json_file, "w") {|f|
          f.write(json)
      }
    }

    # check if user provides icons
    rectangle_icon = 'icon1024x768.png'
    icons_directory = File.join(File.join(File.join(proj_tmp_dir, 'StickerPackExtension'), 'Stickers.xcstickers'), "iMessage App Icon.stickersiconset")
    if File.exist?(rectangle_icon)
      processor = ImageResizer::Processor.new
      sizes = ['32x24', '27x20', '60x45', '74x55', '67x50']
      sizes.each {|size|
        width = size.split('x')[0].to_i
        height = size.split('x')[1].to_i
        [1, 2, 3].each {|scale|
          scale_string = ( scale > 1 ) ? "@#{scale}x.png" : ".png"
          filename = "#{size}#{scale_string}"
          image = ImageResizer::TempObject.new(File.new(rectangle_icon))
          tempfile = processor.resize(image, :width => scale * width, :height => scale * height)
          File.open(File.join(icons_directory, filename), 'wb') { |f| f.write(File.read(tempfile)) }
        }
      }
      square_sizes = ['29x29']
      crop_length = ((1024.0-768.0)/2.0)/1024.0
      square_sizes.each {|size|
        width = size.split('x')[0].to_i
        upper_left = [crop_length, 0]
        lower_right = [1-crop_length, 1]
        [1, 2, 3].each {|scale|
          scale_string = ( scale > 1 ) ? "@#{scale}x.png" : ".png"
          filename = "#{size}#{scale_string}"
          image = ImageResizer::TempObject.new(File.new(rectangle_icon))
          tempfile = processor.crop_to_frame_and_resize(image,
                                            :upper_left => upper_left,
                                            :lower_right => lower_right,
                                            :width => scale * width
                                            )
          File.open(File.join(icons_directory, filename), 'wb') { |f| f.write(File.read(tempfile)) }

          # ipad 2x
          if scale == 2
            filename2 = "#{size}@#{scale}x-1.png"
            File.open(File.join(icons_directory, filename2), 'wb') { |f| f.write(File.read(tempfile)) }
          end
        }
      }
    end

    # cp the app store image
    FileUtils.cp rectangle_icon, File.join(icons_directory, "#{info['name']}.png")

    # copy the modified template to output directory
    FileUtils.rm_rf './output'
    FileUtils.cp_r proj_tmp_dir, './output'

    # Rename project
    xcodeproj = File.join('./output', 'Awesome Stickers.xcodeproj')
    new_xcodeproj = File.join('./output', "#{info['name']}.xcodeproj")
    pbxproj = File.join(xcodeproj, 'project.pbxproj')
    new_pbxproj = File.read(pbxproj).gsub('Awesome Stickers', info['name'])
    xcworkspacedata = File.join(File.join(xcodeproj, 'project.xcworkspace'), 'contents.xcworkspacedata')
    new_xcworkspacedata = File.read(xcworkspacedata).gsub('Awesome Stickers', info['name'])
    File.open(pbxproj, 'wb') {|f| f.write(new_pbxproj)}
    File.open(xcworkspacedata, 'wb') {|f| f.write(new_xcworkspacedata)}
    File.rename xcodeproj, new_xcodeproj

    info_plist = File.join(File.join('./output', 'TestStickers'), 'Info.plist')
    info_plist_content = File.read(info_plist)
    new_info_plist_content = info_plist_content.gsub('Awesome Stickers', info['name'])
    File.open(info_plist, 'wb') {|f| f.write(new_info_plist_content)}

    info_plist = File.join(File.join('./output', 'StickerPackExtension'), 'Info.plist')
    info_plist_content = File.read(info_plist)
    new_info_plist_content = info_plist_content.gsub('Awesome Stickers', info['name'])
    File.open(info_plist, 'wb') {|f| f.write(new_info_plist_content)}

    puts "Done"
  end

  def self.download_template(tmp_dir, template_dir)
    puts 'No templates. Downloading ...'
    if File.exist?(template_dir)
      FileUtils.rm_rf template_dir
    end
    parent = Pathname.new(template_dir).parent()
    puts parent
    if File.exist?(parent)
      FileUtils.rm_rf File.join(parent, 'iOStickersTemplate-master')
    end
    open('https://github.com/nicnocquee/iOStickersTemplate/archive/master.zip') {|f|
      master_zip = File.join(tmp_dir, "master.zip")
      File.open(master_zip,"wb") do |file|
        file.puts f.read
        puts 'Extracting sticker template ...'
        Zip::File.open(master_zip) do |zip_file|
          zip_file.each do |entry|
            # puts "\tExtracting #{entry.name}"
            dest_file = File.join(tmp_dir, entry.name)
            entry.extract(dest_file)
          end
          File.rename(File.join(tmp_dir, 'iOStickersTemplate-master'), template_dir)
          puts "Template downloaded."
          File.delete(master_zip)
        end
      end
    }
  end
end
