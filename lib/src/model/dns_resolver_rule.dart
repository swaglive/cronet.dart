import 'dart:io';

import 'package:equatable/equatable.dart';

class DnsResolverRules {
  factory DnsResolverRules.create({ResolvedDomain? domain}) {
    final DnsResolverRules instance = DnsResolverRules._();
    if (domain != null) {
      instance.domains.add(domain);
    }
    return instance;
  }

  DnsResolverRules._() : domains = <ResolvedDomain>[];

  final List<ResolvedDomain> domains;

  bool update({required String domain, required InternetAddress host}) =>
      updateResolveHost(ResolvedDomain(domain: domain, host: host));

  bool updateResolveHost(ResolvedDomain resolvedDomain) {
    final int index = domains
        .indexWhere((element) => element.domain == resolvedDomain.domain);
    final bool isExist = index >= 0;
    final bool isEqual = isExist ? domains[index] == resolvedDomain : false;
    if (isExist) {
      domains[index] = resolvedDomain;
    } else {
      domains.add(resolvedDomain);
    }
    return !isEqual;
  }

  void remove({required String domain}) {
    domains.removeWhere((element) => element.domain == domain);
  }

  String toRules() => domains.map((e) => e.toRule()).join(',');
}

class ResolvedDomain extends Equatable {
  const ResolvedDomain({required this.domain, required this.host});

  final String domain;
  final InternetAddress host;

  @override
  List<Object?> get props => [domain, host];

  String toRule() => 'MAP $domain ${host.address}';
}
