// lib/core/widgets/entity_by_id_loader.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../errors/failures.dart';
import 'shimmer_skeleton.dart';

/// Resolves a single entity either directly by id via [fetchSingle] (preferred, O(1))
/// or from a reactive list stream [watch] so an id-based deep link (e.g. `/album?id=5`)
/// can render without a typed route `extra`.
///
/// Shows a skeleton while the first emission arrives and a plain "not found"
/// scaffold when the id matches nothing.
class EntityByIdLoader<T> extends StatefulWidget {
  final Future<Result<T?>> Function()? fetchSingle;
  final Stream<Result<List<T>>> Function()? watch;
  final bool Function(T item)? match;
  final Widget Function(BuildContext context, T item) builder;
  final String notFoundMessage;

  const EntityByIdLoader({
    super.key,
    this.fetchSingle,
    this.watch,
    this.match,
    required this.builder,
    required this.notFoundMessage,
  }) : assert(fetchSingle != null || (watch != null && match != null),
            'Must provide either fetchSingle or both watch and match');

  @override
  State<EntityByIdLoader<T>> createState() => _EntityByIdLoaderState<T>();
}

class _EntityByIdLoaderState<T> extends State<EntityByIdLoader<T>> {
  StreamSubscription? _sub;
  T? _entity;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    if (widget.fetchSingle != null) {
      widget.fetchSingle!().then((res) {
        if (!mounted) return;
        setState(() {
          _entity = res.fold((_) => null, (item) => item);
          _done = true;
        });
      }).catchError((_) {
        if (mounted) setState(() => _done = true);
      });
      return;
    }

    if (widget.watch != null) {
      _sub = widget.watch!().listen(
        (result) {
          result.fold((_) {}, (list) {
            for (final item in list) {
              if (widget.match!(item)) {
                _entity = item;
                break;
              }
            }
          });
          if (!mounted) return;
          setState(() => _done = true);
          _sub?.cancel();
        },
        onError: (_) {
          if (mounted) setState(() => _done = true);
        },
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entity = _entity;
    if (entity != null) return widget.builder(context, entity);
    if (!_done) {
      return Scaffold(
        appBar: AppBar(),
        body: const SkeletonList(padding: EdgeInsets.only(top: 8)),
      );
    }
    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text(widget.notFoundMessage)),
    );
  }
}
