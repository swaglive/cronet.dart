import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:cronet/src/constants.dart';
import 'package:cronet/src/third_party/ffigen/find_resource.dart';

import 'place_binaries.dart';

/// Download `cronet` library from Github Releases.
Future<void> downloadCronetBinaries(String platform) async {
  final logger = Logger.standard();
  final ansi = Ansi(Ansi.terminalSupportsAnsi);
  if (!isCronetAvailable(platform)) {
    final fileName = platform + '.tar.gz';
    logger.stdout('Downloading Cronet for $platform');
    final downloadUrl = cronetBinaryUrl + fileName;
    logger.stdout(downloadUrl);
    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();
      final fileSink = File(fileName).openWrite();
      await response.pipe(fileSink);
      await fileSink.flush();
      await fileSink.close();
      httpClient.close();
    } catch (error) {
      Exception("Can't download. Check your network connection!");
    }
    placeBinaries(platform, fileName);
    logger.stdout(
        '${ansi.green}Done! Cronet support for $platform is now available!'
        '${ansi.none}');
  } else {
    logger.stdout(
        '${ansi.green}Done! Cronet support for $platform was downloaded already'
        '${ansi.none}');
  }
}

class AndroidCommand extends Command<void> {
  @override
  String get description => 'Download Android cronet binaries.';

  @override
  String get name => 'android';

  @override
  void run() {
    downloadCronetBinaries('android');
  }
}

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<void>('download', 'Downloads the cronet binaries.');
  runner.addCommand(AndroidCommand());
  runner.run(args);
}
