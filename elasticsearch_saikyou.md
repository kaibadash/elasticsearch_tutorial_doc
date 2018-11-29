kaibaと申します。

本年はElasticsearch関連でこんなことがありました。

- 業務でElasticsearchを導入する機会に恵まれ
- 技術書典で[検索だけじゃない Elasticsearch 入門](https://kaiba.booth.pm/items/1031664)という本を書き、100冊近く売れ
-  その他、アウトプットもぼちぼち出して
- 中の人johtaniさんにも良くしていただきました

Elasticsearch元年になり、Elasticsearchで年を締めくくろうとしております。

今回は[検索だけじゃない Elasticsearch 入門](https://kaiba.booth.pm/items/1031664)に対する発展編として、
青空文庫検索システムを例に、できる限りわかりやすく書いてみたいと思います。
この本は、僕も時々リファレンス的に見直すことがあり、なかなか良い本だと思いますので是非読んでみてください。

## 何を作るか

青空文庫に[作家別作品一覧拡充版：全て(CSV 形式、UTF-8、zip 圧縮）](https://www.aozora.gr.jp/index_pages/person_all.html)というのがありました。
sjisだろうな〜、文字コード変換やだな〜、と思っていたので、感動しました。
悪しきken_all.csvも見習ってほしい。

これを使って、「青空文庫検索エンジン」を作ろうと目指そうと思います。

## 仕様

Googleをリスペクトしつつ、中を知っている感じの仕様になりますが、以下のようにします。

- サジェストを有効に使って補助したい。ここは単純に前方一致が良い。
  - わがはい =>「吾輩は猫である」
  - みやざわ =>「宮沢賢治」
- もしかして
  - 吾輩は猫であろ =>「吾輩は猫である」
  - 宮沢賢二 =>「宮沢賢治」
- 作品タイトル、著者名で検索できる。ここはサジェストがあるので日本語の検索を意識する。
  - 吾輩は猫 =>「吾輩は猫である」
  - わがはいはねこ =>「吾輩は猫である」
  - みやざわ => 宮沢賢治の書籍がヒット
  - 京都 =>「東京都」はヒットしない。

## 設計

仕様を満たすために以下の設計にします。
業務だと「Googleみたいにして！」って言われることが多いので、ここはちゃんとしておかないと痛い目を見ます。

### サジェスト

- 単純に前方一致させるためにデフォルトのanalyserを使う
- データ名は \*\_サジェストとする
- completionサジェストerという機能で実現します

### もしかして

- こちらも標準のanalyerで単純に近いものを探します。
- termサジェストerという機能で実現します

### 検索

- サジェストである程度  カバーできるはずなので、日本語を意識して検索する
  - 「こんにちは東京都」という書籍に対して、「京都」でヒットさせたくない

## 環境構築

[公式の Docker Image](https://www.docker.elastic.co/)を使ってみます。
Docker知らない人も、怖がらずに。
いやいや、DockerじゃなくてAWS Elasticsearch Serviceでやりたいんだ、という方は、[検索だけじゃない Elasticsearch 入門](https://kaiba.booth.pm/items/1031664)をどうぞ！(しつこい）

```sh
docker pull docker.elastic.co/elasticsearch/elasticsearch:6.5.1
docker run -p 9200:9200 -e "discovery.type=single-node" docker.elastic.co/elasticsearch/elasticsearch:6.5.1
```

なんかElasticsearchのdocker imageをpullしてきて
port 9200で動かした、というのがわかれば十分です。

ついでに、日本語向けのプラグインを入れます。
公式のDocker Imageには日本語プラグイン設定済みのものがなかったので、
職人が手作業で日本語のプラグインを入れちゃいます。
手作業が嫌な人は[こんなかんじで Dockerfile](https://hub.docker.com/r/patorash/elasticsearch-kuromoji/~/dockerfile/)を作ると良いでしょう。
僕が用意しても良かったんですが、こちらの方がわかりやすいかな、と思いまして…。
停止すると挿入したデータは消えちゃいます…。
このへん、Dockerの勉強にも良いかと。

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

\_nodes/pluginsにGETして、kuromojiの存在を確認します。

```sh
curl http://localhost:9200/_nodes/plugins\?pretty -X GET | grep kuromoji
          "name" : "analysis-kuromoji",
          "description" : "The Japanese (kuromoji) Analysis plugin integrates Lucene kuromoji analysis module into elasticsearch.",
          "classname" : "org.elasticsearch.plugin.analysis.kuromoji.AnalysisKuromojiPlugin",
```

良さそう。

## mapping

どのフィールドをどのように解析するか、の設定をします。
日本語の設定が不要であれば、Elasticsearchがよしなにやってくれますので、
 必須の操作ではありません。
今回は日本語を使う要件がありますので設定します。

### 挿入するデータ

以下のデータを入れることにします。

| データ名       | 内容                     | 例                   |
| -------------- | ------------------------ | -------------------- |
| id             | 青空文庫の本ID          | 002672               |
| title          | タイトル                 | 吾輩は猫である       |
| author         | 著者名                   | 夏目漱石             |
| title_yomi     | タイトル（よみがな）       | わがはいはねこである |
| author_yomi    | 著者名（よみがな）         | なつめそうせき       |
| \*\_ja         | 上記の日本語検索用データ |                      |
| \*\_サジェストion | 上記のサジェスト用データ |                      |

`id` は一意のIDでこれをキーにdocumentを更新します。

### mapping

上記のデータを挿入するための設定です。

```mapping.json
{
  "settings": {
    "index": {
      "analysis": {
        "tokenizer": {
          "ja_tokenizer": {
            "type": "kuromoji_tokenizer"
          }
        },
        "analyzer": {
          "ja_analyzer": {
            "type": "custom",
            "tokenizer": "ja_tokenizer"
          }
        }
      }
    }
  },
  "mappings": {
    "books": {
      "dynamic_templates": [
        {
          "ja_string": {
            "match_mapping_type": "string",
            "match": "*_ja",
            "mapping": {
              "type": "text",
              "analyzer": "ja_analyzer"
            }
          }
        },
        {
          "yomi_string": {
            "match_mapping_type": "string",
            "match": "*_suggestion",
            "mapping": {
              "type": "completion"
            }
          }
        }
      ],
      "properties": {
        "title": {
          "type": "text",
          "copy_to": ["title_ja", "title_suggestion"]
        },
        "title_ja": {
          "type": "text",
          "store": true
        },
        "title_yomi": {
          "type": "text",
          "copy_to": ["title_yomi_suggestion"]
        },
        "author": {
          "type": "text",
          "copy_to": ["author_ja", "author_suggestion"]
        },
        "author_ja": {
          "type": "text",
          "store": true
        },
        "author_yomi": {
          "type": "text",
          "copy_to": ["author_yomi_suggestion"]
        }
      }
    }
  }
}
```

- title, authorをコピーしてtitle_ja, author_jaを作成しています。
- \*\_jaはcustum analyzerを定義し、tokenizerに `kuromoji_tokenizer` を使用しています。

設定を反映します。

```sh
curl http://localhost:9200/aozora\?pretty -X PUT -H "Content-Type: application/json" -d @mapping.json
```

## CSVの全データを挿入する

### プログラム

雑にもほどがありますが、GemなしのRubyで書いてみました。

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
    # NOTE: IDはURLの末尾に指定します。RESTですね。
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
    # メタプロするとパラメータの追加に動的に対応できそう。メタプロは用法用量を正しく(略)
    {title: @title, title_yomi: @title_yomi, author: @author, author_yomi: @author_yomi}.to_json
  end
end

# NOTE: CSVを同じディレクトリにおいてね!
# FIXME: 本来であれば一括で挿入(bulk insert)できるのでそうした方が速いよ！
CSV.foreach("list_person_all_extended_utf8.csv") do |line|
  next unless line[INDEX_ID] =~ /^[0-9]+/
  p line[INDEX_TITLE]
  Book.new(
        line[INDEX_ID],
        line[INDEX_TITLE],
        line[INDEX_TITLE_YOMI],
        line[INDEX_AUTHOR_SEI] + line[INDEX_AUTHOR_MEI],
        line[INDEX_AUTHOR_SEI_YOMI] + line[INDEX_AUTHOR_MEI_YOMI]
  ).post_index
end
```

## 要件を確認していく

### サジェスト

前方一致でサジェストが得られるか試します。

```suggest_query.json
{
  "suggest": {
    "book_suggest_title": {
      "prefix": "わがは",
      "completion": {
        "field": "title_yomi"
      }
    },
    "book_suggest_author": {
      "prefix": "わがは",
      "completion": {
        "field": "author_yomi"
      }
    }
  }
}
```

タイトル、著者のよみがなから探します。
今回はauthorでヒットしませんが、実際のクエリを意識してこのようにしています。

```sh
curl http://localhost:9200/aozora/books/_search\?pretty -X POST -H "Content-Type: application/json" -d @suggest_query.json
```

```json
  "suggest" : {
    "book_suggest_author" : [
      {
        "text" : "わがは",
        "offset" : 0,
        "length" : 3,
        "options" : [ ]
      }
    ],
    "book_suggest_title" : [
      {
        "text" : "わがは",
        "offset" : 0,
        "length" : 3,
        "options" : [
          {
            "text" : "『わがはいはねこである』げへんじじょ",
            "_index" : "aozora",
            "_type" : "books",
            "_id" : "002672",
            "_score" : 1.0,
            "_source" : {
              "title" : "『吾輩は猫である』下篇自序",
```

良さそう！

### もしかして

```term_suggest_query.json
{
  "suggest": {
    "suggest_title_yomi": {
      "text": "なつめそうせい",
      "term": {
        "field": "title_yomi_suggestion"
      }
    },
    "suggest_title": {
      "text": "なつめそうせい",
      "term": {
        "field": "title_suggestion"
      }
    },
    "suggest_author_yomi": {
      "text": "なつめそうせい",
      "term": {
        "field": "author_yomi_suggestion"
      }
    },
    "suggest_author": {
      "text": "なつめそうせい",
      "term": {
        "field": "author_suggestion"
      }
    }
  }
}
```

作者名読みのサジェストを得る例です。
今回はサジェスト_author_yomi以外でヒットしませんが、実際のクエリを意識してこのようにしています。

```sh
curl http://localhost:9200/aozora/books/_search\?pretty -X POST -H "Content-Type: application/json" -d @term_suggest_query.json
```

```
    "suggest_author_yomi" : [
      {
        "text" : "なつめそうせい",
        "offset" : 0,
        "length" : 7,
        "options" : [
          {
            "text" : "なつめそうせき",
            "score" : 0.85714287,
            "freq" : 105
          }
        ]
      }
    ],
```

よさそう！

#### 作品タイトル、著者名で検索

今回は日本語の設定をしなかったので、「こん」でも「こんにちは」がヒットし、意図しないものが多くヒットします。

`_search` のエンドポイントにクエリのjsonを投げつけるだけですが、クエリを考える必要があります。
プログラムからクエリを投げることを考えつつ、クエリにするとこんな感じでしょうか？

```query.json
{
  "query": {
    "bool": {
      "should": [
        {
          "match": {
            "title": "吾輩"
          }
        },
        {
          "match": {
            "title_yomi": "吾輩"
          }
        },
        {
          "match": {
            "author": "吾輩"
          }
        },
        {
          "match": {
            "author_yomi": "吾輩"
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

```json
  "hits" : {
    "total" : 63,
    "max_score" : 10.369913,
    "hits" : [
      {
        "_index" : "aozora",
        "_type" : "books",
        "_id" : "058086",
        "_score" : 10.369913,
        "_source" : {
          "title" : "我輩の智識吸収法",
          "title_yomi" : "わがはいのちしききゅうしゅうほう",
          "author" : "大隈重信",
          "author_yomi" : "おおくましげのぶ"
        }
      },
```

よさそう。

## まとめ

- 検索もサジェストも難しい！
- Googleみたいに！　って絶対言われるから、ちゃんと調査、設計して合意を取るのが重要かも。
- ElasticsearchもGoogleもすごい！
