// Extracts a tar.gz file.
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:cronet/src/constants.dart';
import 'package:path/path.dart';

void extract(String fileName, [String dir = '']) {
  final tarGzFile = File(fileName).readAsBytesSync();
  final archive = GZipDecoder().decodeBytes(tarGzFile, verify: true);
  final tarData = TarDecoder().decodeBytes(archive, verify: true);
  for (final file in tarData) {
    final filename = file.name;
    if (file.isFile) {
      final data = file.content as List<int>;
      File(dir + filename)
        ..createSync(recursive: true)
        ..writeAsBytesSync(data);
    } else {
      Directory(dir + filename).createSync(recursive: true);
    }
  }
}

/// Places downloaded mobile binaries to proper location.
void placeMobileBinaries(String platform, String fileName) {
  Directory(androidPaths['cronet.jar']!).createSync(recursive: true);
  Directory(tempAndroidDownloadPath['cronet.jar']!).listSync().forEach((jar) {
    if (jar is File) {
      jar.renameSync(join(androidPaths['cronet.jar']!, basename(jar.path)));
    }
  });
  Directory(androidPaths['cronet.so']!).createSync(recursive: true);
  Directory(tempAndroidDownloadPath['cronet.so']!)
      .listSync(recursive: true)
      .forEach((cronet) {
    if (cronet is File) {
      Directory(join(androidPaths['cronet.so']!, basename(cronet.parent.path)))
          .createSync(recursive: true);
      cronet.renameSync(join(androidPaths['cronet.so']!,
          basename(cronet.parent.path), basename(cronet.path)));
    }
  });
}

/// Places downloaded binaries to proper location.
void placeBinaries(String platform, String fileName) {
  final logger = Logger.standard();
  final ansi = Ansi(Ansi.terminalSupportsAnsi);
  logger.stdout('${ansi.yellow}Extracting Cronet for $platform${ansi.none}');
  Directory(binaryStorageDir).createSync(recursive: true);
  extract(fileName, binaryStorageDir);
  if (mobilePlatforms.contains(platform)) {
    placeMobileBinaries(platform, fileName);
  }
  logger.stdout('Cleaning up unused files...');

  File(fileName).deleteSync();
}
