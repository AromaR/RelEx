function (
  embedding_dim = 300, embedding_projection_dim = null,
  offset_type = "entity_only", offset_embedding_dim = null, freeze_offset_embeddings = true,
  max_len = 200
  ) {

  local use_embedding_projection = (embedding_projection_dim != null),
  local use_offset_embeddings = (offset_embedding_dim != null),

  local combined_offset_embedding_dim = if use_offset_embeddings && (offset_type != "sine") then 2 * offset_embedding_dim else 0,
  local text_encoder_input_dim = combined_offset_embedding_dim
                                 + (if use_embedding_projection then embedding_projection_dim else embedding_dim),

  "dataset_reader": {
    "type": "semeval2010_task8",
    "max_len": max_len,
    "token_indexers": {
      "tokens": {
        "type": "single_id",
        "lowercase_tokens": true
      },
    },
  },
  
  "train_data_path": "../relex-data/semeval_2010_task_8/train.jsonl",
  "validation_data_path": "../relex-data/semeval_2010_task_8/dev.jsonl",

  "model": {
    "type": "basic_relation_classifier",
    [if use_embedding_projection then "embedding_projection_dim"]: embedding_projection_dim,
    "verbose_metrics": false,
    "text_field_embedder": {
      "tokens": {
        "type": "embedding",
        "pretrained_file": "https://s3-us-west-2.amazonaws.com/allennlp/datasets/glove/glove.6B.300d.txt.gz",
        "embedding_dim": embedding_dim,
        "trainable": false
      },
    },
    [if use_offset_embeddings then "offset_embedder_head"]: {
      "type": offset_type,
      "n_position": max_len,
      "embedding_dim": offset_embedding_dim,
    },
    [if use_offset_embeddings then "offset_embedder_tail"]: {
      "type": offset_type,
      "n_position": max_len,
      "embedding_dim": offset_embedding_dim,
    },
    "text_encoder": {
      "type": "seq2seq_pool",
      "encoder": {
        "type": "lstm",
        "input_size": text_encoder_input_dim,
        "hidden_size": 2048,
        "bidirectional": true,
        "num_layers": 1,
      },
      "pooling": "mean"
    },
    "classifier_feedforward": {
      "input_dim": 4096,
      "num_layers": 1,
      "hidden_dims": [19],
      "activations": ["linear"],
      "dropout": [0.0]
    },
    "initializer": [
      ["text_encoder._encoder._module.weight.*", "kaiming_uniform"],
      ["offset_embedder.*weight.*", {"type": "sparse", "sparsity": 0.2}],
      [".*embedding_projection.*weight.*", "kaiming_uniform"],
      [".*embedding_projection.*bias.*", {"type": "constant", "val": 0}],
    ],
  },

  "iterator": {
    "type": "bucket",
    "sorting_keys": [["text", "num_tokens"]],
    "batch_size": 64
  },

  "trainer": {
    "num_epochs": 200,
    "patience": 10,
    "cuda_device": 0,
    "num_serialized_models_to_keep": 1,
    // "grad_clipping": 5.0,
    "validation_metric": "+f1-measure-overall",
    "optimizer": {
      "type": "adam",
      "lr": 1e-3
    },
    "no_grad": [
      "text_encoder.*",
    ] + (if freeze_offset_embeddings then ["offset_embedder.*"] else [])
      + (if use_embedding_projection then [".*embedding_projection"] else []),
  }
}
