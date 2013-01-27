# coding:utf-8
# Title: とうほう☆ストラテジーリプレイファイル プレイヤー名マスキング スクリプト
# Desc: リプレイファイルに含まれるプレイヤー名を*でマスキングします。
#       手抜き実装なのでリプレイファイルによっては動かない可能性が大いにあります。
# Author : nanashi(twitter:@tako774)
# Lisence: NYSL

require 'zlib'
require 'stringio'

DEBUG = true
SCRIPT_NAME = "とうほう☆ストラテジー(ver.1.44-) リプレイファイル プレイヤー名マスキングツール"
REVISION = 20130127
MIN_VALID_VERSION = 5144

# GZIP マジックナンバー
GZIP_IDENTIFIER = "\x1F\x8B".force_encoding('ASCII-8BIT')
# マスク変換後データ
MASK_CHAR_FIRST = "*".encode('UTF-16LE', 'UTF-8').force_encoding('ASCII-8BIT')
MASK_FILLER = " ".encode('UTF-16LE', 'UTF-8').force_encoding('ASCII-8BIT')
MASK_FILLER_UTF8 = " ".force_encoding('ASCII-8BIT')
# ヘッダ内区切り文字
HEADER_SEPARATOR = "\xFF\xFF\xFF\xFF".force_encoding('ASCII-8BIT')
# 展開後本体データのヘッダとボディの区切り（超適当）
INFLATED_BODY_START = "\xFF\xFF\xFF\xFF".force_encoding('ASCII-8BIT')

# ヘッダ中バイト位置
OFFSET_MAP_CLASSPATH = 0x19 # マップクラスパス長さ位置
OFFSET_VERSION = 0x0C # バージョン情報位置

# 変数宣言
src_path = nil  # 元のリプレイファイル
dst_path = nil  # 変換後のリプレイファイル
names_data = [] # プレイヤー名データ
names_plus_length_data = [] # 名前の長さデータ4バイトを先頭につけたプレイヤー名データ
twitter_ids = []
screen_names = []
icon_urls = []
ranks = []
header = nil    # ヘッダ
version = nil # バージョン数字

# リプレイデータのロード
def load_replay_data(path)
  data = File.open(path, 'rb').read
  header = data[0..data.index(GZIP_IDENTIFIER) - 1]
  body_compressed = data[data.index(GZIP_IDENTIFIER)..(data.length - 1)]
  {
    :header => header,
    :body_compressed => body_compressed
  }
end

# 文字列 gzip 展開
# ヘッダが欠落しているので、ストリームとして読み込まないと
# incorrect header check (Zlib::DataError) が発生する
def inflate_data(data)
  Zlib::GzipReader.wrap(StringIO.new(data, 'rb'), encoding: 'ASCII-8BIT').read
end

# 文字列 gzip 圧縮
def deflate_data(data)
  Zlib::Deflate.deflate(data, Zlib::BEST_COMPRESSION)
end

# 指定されたオフセットの先頭4バイトから長さをとり、
# 先頭5バイト目から取得した長さ分のデータを取得し返す
# また、offset として 4 + 長さ分すすめた offset を返す
def get_offset_data(data, offset)
  # puts offset.to_s(16)
  length = data[offset..offset + 3].unpack('I')[0]
  [offset + 4 + length, data[(offset + 4)..(offset + 4 + length - 1)]]
end

# バージョン文字列取得
def get_version(header)
  offset, version = get_offset_data(header, OFFSET_VERSION)
  version
end

# プレイヤー情報取得
def get_players_info(header)
  offset = nil
  player_num = nil
  names_data = []
  names_plus_length_data = []
  twitter_ids = []
  screen_names = []
  icon_urls = []
  ranks = []
  
  ## ゲーム情報部分
  # マップクラスパス読み飛ばし
  offset, = get_offset_data(header, OFFSET_MAP_CLASSPATH)
  # プレイヤー数取得
  player_num = header[offset..(offset + 3)].unpack('I')[0]
  offset += 4
  puts "プレイヤー数 #{player_num}"
  
  ## プレイヤー情報部分
  player_num.times do
    is_com = false
    
    # プレイヤー順序番号読み飛ばし
    offset += 4
    # プレイヤー名取得
    offset_faction, name = get_offset_data(header, offset)
    names_data << name
    names_plus_length_data << header[offset..(offset_faction - 1)]
    # 勢力読み飛ばし
    offset_team_id, = get_offset_data(header, offset_faction)
    # チーム番号読み飛ばし
    offset_bomb = offset_team_id + 4
    # ボム読み飛ばし
    3.times do
      offset_bomb, = get_offset_data(header, offset_bomb)
    end
    offset_is_com = offset_bomb
    # COM かどうか
    is_com = header[offset_is_com] == "\x01" ? true : false 
    offset_is_observer = offset_is_com + 1
    # 観戦者かどうか読み飛ばし
    offset_twitter_id = offset_is_observer + 1
    # twitter 情報取得
    offset_screen_name, twitter_id = get_offset_data(header, offset_twitter_id)
    offset_icon_url, screen_name = get_offset_data(header, offset_screen_name)
    offset_rank, icon_url = get_offset_data(header, offset_icon_url)
    twitter_ids << twitter_id
    screen_names << screen_name
    icon_urls << icon_url
    # ランク情報取得
    offset, rank = get_offset_data(header, offset_rank)
    ranks << rank
    
    if is_com then
      print " [ COM ]" if DEBUG 
    else
      print " #{name.unpack('a*')[0].encode('Windows-31J', 'UTF-16LE')} " if DEBUG 
      print " #{twitter_id.unpack('a*')[0].encode('Windows-31J', 'UTF-16LE')} " if DEBUG 
      print " #{screen_name.unpack('a*')[0].encode('Windows-31J', 'UTF-16LE')} " if DEBUG 
      print " #{icon_url.unpack('a*')[0].encode('Windows-31J', 'UTF-16LE')} " if DEBUG 
      print " #{rank.unpack('a*')[0].encode('Windows-31J', 'UTF-16LE')} " if DEBUG 
    end
    puts
  end
  
  [names_data, names_plus_length_data, twitter_ids, screen_names, icon_urls, ranks]
end

def print_usage
  puts "使い方：#{File.basename(__FILE__)} <変換元リプレイファイル>"
end

def print_file_not_found
  puts "ERROR:指定された変換元リプレイファイルが見つかりません"
end

### メイン処理
puts "★#{SCRIPT_NAME} Rev.#{REVISION}"
puts 

# 引数処理
src_path = ARGV.shift

if src_path == nil then
  print_usage
  exit
elsif !(File.exist? src_path) then
  print_file_not_found
  exit
end

# 出力ファイルパスを決定
dst_path = "#{File.dirname(src_path)}/#{File.basename(src_path, '.*')}_masked#{File.extname(src_path)}"
print "■変換元ファイル："
puts src_path
print "■変換先ファイル："
puts dst_path

# 元リプレイファイルを読みこみ
puts "変換元リプレイファイル読み込み..."
src_data = load_replay_data(src_path)
header = src_data[:header]

# ヘッダからバージョン情報を取得
version = get_version(header).encode('Windows-31J', 'UTF-16LE')
puts "本体バージョン文字列: #{version} (Ver.#{version[1]}.#{version[2..3]})"
puts "！警告：リプレイのバージョンが未対応です。続行しますが成功しない可能性大です。" if version.to_i < MIN_VALID_VERSION

# ヘッダからプレイヤー情報取得
puts "プレイヤー情報取得..."
names_data, names_plus_length_data, twitter_ids, screen_names, icon_urls, ranks = get_players_info(header)

# ヘッダのプレイヤー名をマスキング
puts "選択画面プレイヤー名マスキング..."
names_data.each do |name_data|
  header.sub!(
    name_data,
    MASK_CHAR_FIRST +
    MASK_FILLER * ((name_data.length - MASK_CHAR_FIRST.length) / MASK_FILLER.length)
  )
end

# 本体データのプレイヤー名マスキング
puts "対戦画面プレイヤー名マスキング..."
body = inflate_data(src_data[:body_compressed])
body_header = body[0..body.index(INFLATED_BODY_START) - 1]
body_body = body[body.index(INFLATED_BODY_START)..(body.length - 1)]
names_plus_length_data.each do |name_data_plus_length|
  body_header.sub!(
    name_data_plus_length,
    name_data_plus_length[0..3] +
    MASK_CHAR_FIRST +
    MASK_FILLER * ((name_data_plus_length.length - 4 - MASK_CHAR_FIRST.length) /  MASK_FILLER.length)
  )
end
# 本体データの本体部はUTF-8
puts "チャットのプレイヤー名マスキング..."
names_data.map do |name_data|
  name_data.encode('UTF-8', 'UTF-16LE').force_encoding('ASCII-8BIT')
end.each do |name_data_utf8|
  body_body.gsub!(name_data_utf8, MASK_FILLER_UTF8 * (name_data_utf8.length / MASK_FILLER_UTF8.length))
end

# ヘッダの twitter 情報をマスキング
puts "twitter 情報をマスキング..."
(twitter_ids + screen_names + icon_urls).each do |tw_str|
  header.sub!(tw_str, MASK_FILLER * (tw_str.length / MASK_FILLER.length)) if tw_str != ""
  body_header.sub!(tw_str, MASK_FILLER * (tw_str.length / MASK_FILLER.length)) if tw_str != ""
end
# 本体の twitter 情報をマスキング
(twitter_ids + screen_names + icon_urls).map do |tw_str|
  tw_str.encode('UTF-8', 'UTF-16LE').force_encoding('ASCII-8BIT')
end.each do |tw_str_utf8|
  body_body.gsub!(tw_str_utf8, MASK_FILLER_UTF8 * (tw_str_utf8.length / MASK_FILLER_UTF8.length))
end

# ヘッダのランク情報をマスキング
puts "ランク情報をマスキング..."
ranks.each do |rank|
  header.sub!(rank, MASK_FILLER * (rank.length / MASK_FILLER.length)) if rank != ""
  body_header.sub!(rank, MASK_FILLER * (rank.length / MASK_FILLER.length)) if rank != ""
end

body = body_header + body_body

# 新しいファイルを生成
puts "変換後ファイル出力..."
File.open(dst_path, 'wb') do |io|
  io.write header
  Zlib::GzipWriter.wrap(io, Zlib::BEST_COMPRESSION, encoding: 'ASCII-8BIT') do |gz|
    gz.write body
  end
end

puts 
puts "リプレイファイル変換処理が正常に終了しました"

