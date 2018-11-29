# 青空文庫検索サイトの作り方を 1 から丁寧に丁寧に解説してみる

kaiba と申します。
業務で Elasticsearch を導入する機会に恵まれ、技術書典で[検索だけじゃない Elasticsearch 入門](https://kaiba.booth.pm/items/1031664)という本を書きました。
僕も時々リファレンス的に見直すことがあり、良い本だな、とひしひしと感じておりますので、是非読んでみてください。
[収支報告](https://pokosho.com/b/archives/3251)も是非御覧ください。

今回は[検索だけじゃない Elasticsearch 入門](https://kaiba.booth.pm/items/1031664)の発展編として、
青空文庫検索システムを例に、できる限りわかりやすく書いてみたいと思います。

## 何を作るか

青空文庫に[作家別作品一覧拡充版：全て(CSV 形式、UTF-8、zip 圧縮）](https://www.aozora.gr.jp/index_pages/person_all.html)というのがありました。
sjis だろうな〜、文字コード変換やだな〜、と思っていたので、感動しました。
悪しき ken_all.csv も見習ってほしい。

これを使って、「青空文庫検索アプリ」を作ろうと目指そうと思います。

## 仕様

Google をリスペクトしつつ、中を知っている感じの仕様になりますが、以下のようにします。

- サジェストを有効に使って補助したい。ここは単純に前方一致が良い。
  - わがはい => 「吾輩は猫である」
  - みやざわ => 「宮沢賢治」
- 作品タイトル、著者名で検索できる。ここはサジェストがあるので日本語の検索を意識する。
  - 吾輩は猫 => 「吾輩は猫である」
  - わがはいはねこ => 「吾輩は猫である」
  - みやざわ => 宮沢賢治の書籍がヒット
  - 京都 => 「東京都」はヒットしない。
- もしかして
  - 吾輩は猫であろ => 「吾輩は猫である」
  - 宮沢賢二 => 「宮沢賢治」

##　設計

仕様を満たすために以下の設計にします。
業務だと「Googleみたいにして！」って言われることが多いので、ここはちゃんとしておかないと痛い目を見ます。

### サジェスト

- 単純に前方一致させるためにデフォルトの analyser を使う
- データ名は \*\_suggest とする

### 検索

- サジェストである程度カバーできるはずなので、日本語を意識して検索する
  - 「こんにちは東京都」という書籍に対して、「京都」でヒットさせたくない

## 環境構築

[公式の Docker Image](https://www.docker.elastic.co/)を使ってみます。
Docker 知らない人も、怖がらずに。
いやいや、Docker じゃなくて AWS Elasticsearch Service でやりたいんだ、という方は、[検索だけじゃない Elasticsearch 入門](https://kaiba.booth.pm/items/1031664)をどうぞ！(しつこい)

```sh
docker pull docker.elastic.co/elasticsearch/elasticsearch:6.5.1
docker run -p 9200:9200 -e "discovery.type=single-node" docker.elastic.co/elasticsearch/elasticsearch:6.5.1
```

なんか Elasticsearch の docker image を pull してきて
port 9200 で動かした、というのがわかれば十分です。

ついでに、日本語向けのプラグインを入れます。
公式の Docker Image には日本語プラグイン設定済みのものがなかったので、
職人が手作業で日本語のプラグインを入れちゃいます。
手作業が嫌な人は[こんなかんじで Dockerfile](https://hub.docker.com/r/patorash/elasticsearch-kuromoji/~/dockerfile/)を作ると良いでしょう。

```sh
# コンテナIDを調べる
docker ps
CONTAINER ID        IMAGE                                                 COMMAND                  CREATED             STATUS              PORTS                              NAMES
0d008241f0e9        docker.elastic.co/elasticsearch/elasticsearch:6.5.1   "/usr/local/bin/dock…"   33 seconds ago      Up 32 seconds       0.0.0.0:9200->9200/tcp, 9300/tcp   festive_bhaskara

# コンテナにshでつなぐインストール
$ docker exec -it 0d008241f0e9 sh

sh-4.2# elasticsearch-plugin install analysis-kuromoji
-> Downloading analysis-kuromoji from elastic
[=================================================] 100%??
-> Installed analysis-kuromoji

# 再起動して反映
exit
docker restart 0d008241f0e9
```

\_nodes/plugins に GET して、kuromoji の存在を確認します。

```sh
curl http://localhost:9200/_nodes/plugins\?pretty -X GET | grep kuromoji
          "name" : "analysis-kuromoji",
          "description" : "The Japanese (kuromoji) Analysis plugin integrates Lucene kuromoji analysis module into elasticsearch.",
          "classname" : "org.elasticsearch.plugin.analysis.kuromoji.AnalysisKuromojiPlugin",
```

良さそう。

[http://localhost:9200/](http://localhost:9200/) にアクセスするとなんか動いてるっぽい json が出るはずです。

## mapping

サジェストはデフォルトのAnalyzerで良さそうですが、検索は日本語を扱う必要があります。

```json
TODO: 
```


### 要件を確認していく

#### サジェスト

前方一致でサジェストが得られるか試します。

```suggest_query.json
{
  "book_suggest": {
    "text": "わがはい",
    "completion": {
      "field": "title_yomi"
    }
  }
}

```

```sh
curl http://localhost:9200/aozora/books/_suggest\?pretty -X POST -H "Content-Type: application/json" -d @suggest_query.json
```

#### 作品タイトル、著者名で検索

今回は日本語の設定をしなかったので、「こん」でも「こんにちは」がヒットし、意図しないものが多くヒットします。

`_search` のエンドポイントにクエリの json を投げつけるだけですが、クエリを考える必要があります。
プログラムからクエリを投げることを考えつつ、クエリにするとこんな感じでしょうか？

```query.json
{
  "query": {
    "bool": {
      "should": [
        {
          "match": {
            "title": "吾輩は猫である"
          }
        },
        {
          "match": {
            "title_yomi": "吾輩は猫である"
          }
        },
        {
          "match": {
            "author": "吾輩は猫である"
          }
        },
        {
          "match": {
            "author_yomi": "吾輩は猫である"
          }
        }
      ]
    }
  }
}

```

```sh
curl http://localhost:9200/aozora/books/_search\?pretty -X POST -H "Content-Type: application/json" -d @query.json
```

漢字ではまずまずですが、ひらがなではあんまりでした。




## とりあえず index 作ってデータ入れてみる

早速、動作確認も兼ねて、データを入れてみます。
以下のデータを入れることにします。

| データ名    | 内容               | 例                   |
| ----------- | ------------------ | -------------------- |
| id          | 青空文庫の本 ID    | 002672               |
| title       | タイトル           | 吾輩は猫である       |
| author      | 著者名             | 夏目漱石             |
| title_yomi  | タイトル(よみがな) | わがはいはねこである |
| author_yomi | 著者名(よみがな)   | なつめそうせき       |

`id` は一意の ID でこれをキーに document を更新します。

### index 作成

aozora という名前にしました。

```sh
curl http://localhost:9200/aozora -X PUT
```

```json
{ "acknowledged": true, "shards_acknowledged": true, "index": "books" }
```

よさそう。

一応 get しておく。pretty をつけると見やすくなるよ。

```sh
curl http://localhost:9200/aozora\?pretty
```

```json
{
  "books": {
    "aliases": {},
    "mappings": {},
    "settings": {
      "index": {
        "creation_date": "1543144973728",
        "number_of_shards": "5",
        "number_of_replicas": "1",
        "uuid": "N_RoGBW8SwGzvNSiCEqdXA",
        "version": {
          "created": "6050199"
        },
        "provided_name": "aozora"
      }
    }
  }
}
```

よさそう。

### document 挿入

document 名は books とした。

```json
{
  "title": "吾輩は猫である",
  "title_yomi": "わがはいはねこである",
  "author": "夏目漱石",
  "author_yomi": "なつめそうせき"
}
```

最近の Elasticsearch は `Content-Type: application/json` で送る必要があります。
つけないとその旨のエラーが 得られるので、怖がる必要はありません。

```
curl http://localhost:9200/aozora/books/002672\?pretty -X POST -H "Content-Type: application/json" -d '{"title": "吾輩は猫である", "title_yomi": "わがはいはねこである", "author": "夏目漱石", "author_yomi": "なつめそうせき"}'
```

id は URL の末尾に指定しています。
RESTful API の流儀ですね。

```json
{
  "_index": "aozora",
  "_type": "books",
  "_id": "DiKoSmcBGDjlSKvodF06",
  "_version": 1,
  "result": "created",
  "_shards": {
    "total": 2,
    "successful": 1,
    "failed": 0
  },
  "_seq_no": 0,
  "_primary_term": 1
}
```

よさそう。

mapping 情報を見ておく。

```
curl http://localhost:9200/aozora/_mapping\?pretty
```

```json
// 中略
"title" : {
  "type" : "text",
  "fields" : {
    "keyword" : {
      "type" : "keyword",
      "ignore_above" : 256
    }
  }
},
// 中略
```

よさそう。全部 text で何の面白みもありません。

### CSV のデータを全部  挿入する

雑にもほどがありますが…。

```ruby
require "csv"
require "net/http"
require "uri"
require "json"

INDEX_ID = 0
INDEX_TITLE = 1
INDEX_TITLE_YOMI = 2
INDEX_AUTHOR_SEI = 15
INDEX_AUTHOR_MEI = 16
INDEX_AUTHOR_SEI_YOMI = 17
INDEX_AUTHOR_MEI_YOMI = 18

class Book
  # FIXME: 環境ごとに違うはずでこんなところに書いちゃ駄目だぞ!
  ENDPOINT = "http://localhost:9200/aozora"

  def initialize(id, title, title_yomi, author, author_yomi)
    @id = id
    @title = title
    @title_yomi = title_yomi
    @author = author
    @author_yomi = author_yomi
  end

  def post_index
    uri = URI.parse("#{ENDPOINT}/books/#{@id}")
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.request_uri)
    req["Content-Type"] = "application/json"
    req.body = to_json
    res = http.request(req)
    p "#{@title} #{res.response.code}"
  end

  private

  def to_json
    # メタプロするとパラメータの追加に動的に対応できそう
    {title: @title, title_yomi: @title_yomi, auther: @author, auther_yomi: @author_yomi}.to_json
  end
end

# FIXME: 本来であれば一括で挿入(bulk insert)できるのでそうした方が速いよ！
CSV.foreach("list_person_all_extended_utf8.csv") do |line|
  next unless line[INDEX_ID] =~ /^[0-9]+/
  Book.new(
        line[INDEX_ID],
        line[INDEX_TITLE],
        line[INDEX_TITLE_YOMI],
        line[INDEX_AUTHOR_SEI] + line[INDEX_AUTHOR_MEI],
        line[INDEX_AUTHOR_SEI_YOMI] + line[INDEX_AUTHOR_MEI_YOMI]
  ).post_index
end
```

#### もしかして

クエリに近いタイトル、著者名を検索します。

## まとめ

- 日本語の問題は を除き要求仕様を満たすことができました
- 「Elasticsearch すげー！」「Google すげー！」ということを実感するはず
- なので「Google みたいにして！」を安易に受けてはいけません
