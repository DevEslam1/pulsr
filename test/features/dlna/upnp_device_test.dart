// Device-description parsing: namespaced XML, relative control URLs and the
// typed failures the renderer service relies on.
import 'package:flutter_test/flutter_test.dart';
import 'package:pulsr/features/dlna/upnp_device.dart';

const String _namespacedDescription = '<?xml version="1.0"?>'
    '<s:root xmlns:s="urn:schemas-upnp-org:device-1-0">'
    '<s:specVersion><s:major>1</s:major><s:minor>0</s:minor>'
    '</s:specVersion>'
    '<s:device>'
    '<s:deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</s:deviceType>'
    '<s:friendlyName>Living Room TV</s:friendlyName>'
    '<s:manufacturer>Samsung</s:manufacturer>'
    '<s:modelName>UE55</s:modelName>'
    '<s:UDN>uuid:living-room-tv</s:UDN>'
    '<s:serviceList>'
    '<s:service>'
    '<s:serviceType>urn:schemas-upnp-org:service:RenderingControl:1'
    '</s:serviceType>'
    '<s:serviceId>urn:upnp-org:serviceId:RenderingControl</s:serviceId>'
    '<s:controlURL>/upnp/control/rendering</s:controlURL>'
    '</s:service>'
    '<s:service>'
    '<s:serviceType>urn:schemas-upnp-org:service:AVTransport:1'
    '</s:serviceType>'
    '<s:serviceId>urn:upnp-org:serviceId:AVTransport</s:serviceId>'
    '<s:controlURL>control/avt</s:controlURL>'
    '</s:service>'
    '</s:serviceList>'
    '</s:device>'
    '</s:root>';

void main() {
  group('UpnpDeviceDescription.parse', () {
    test('reads namespaced elements and resolves a relative control URL',
        () {
      final description = UpnpDeviceDescription.parse(
        _namespacedDescription,
        location: Uri.parse('http://192.168.1.10:49152/description.xml'),
      );

      expect(description.friendlyName, 'Living Room TV');
      expect(description.manufacturer, 'Samsung');
      expect(description.modelName, 'UE55');
      expect(description.udn, 'uuid:living-room-tv');
      expect(
        description.deviceType,
        'urn:schemas-upnp-org:device:MediaRenderer:1',
      );
      expect(description.isMediaRenderer, isTrue);
      expect(description.identity, 'uuid:living-room-tv');
      expect(
        description.avTransportControlUrl,
        Uri.parse('http://192.168.1.10:49152/control/avt'),
      );
    });

    test('prefers URLBase for relative control URLs', () {
      const xml = '<root><URLBase>http://10.0.0.5:8080/</URLBase>'
          '<device><friendlyName>Kitchen</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:AVTransport:1'
          '</serviceType>'
          '<controlURL>upnp/control/avt</controlURL>'
          '</service></service></serviceList></device></root>';

      final description = UpnpDeviceDescription.parse(
        xml,
        location: Uri.parse('http://192.168.1.10:49152/description.xml'),
      );

      expect(
        description.avTransportControlUrl,
        Uri.parse('http://10.0.0.5:8080/upnp/control/avt'),
      );
    });

    test('decodes XML entities in names and control URLs', () {
      const xml = '<root><device>'
          '<friendlyName>Living Room &amp; Kitchen</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:AVTransport:1'
          '</serviceType>'
          '<controlURL>control/avt?x=1&amp;y=2</controlURL>'
          '</service></service></serviceList></device></root>';

      final description = UpnpDeviceDescription.parse(
        xml,
        location: Uri.parse('http://192.168.1.10:8080/description.xml'),
      );

      expect(description.friendlyName, 'Living Room & Kitchen');
      expect(description.avTransportControlUrl.path, '/control/avt');
      expect(description.avTransportControlUrl.query, 'x=1&y=2');
    });

    test('rejects a description without friendlyName', () {
      const xml = '<root><device><modelName>Anon</modelName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:AVTransport:1'
          '</serviceType>'
          '<controlURL>/avt</controlURL>'
          '</service></service></serviceList></device></root>';

      expect(
        () => UpnpDeviceDescription.parse(
          xml,
          location: Uri.parse('http://192.168.1.10/description.xml'),
        ),
        throwsA(
          isA<UpnpParseError>().having(
            (error) => error.code,
            'code',
            'DLNA_FRIENDLY_NAME',
          ),
        ),
      );
    });

    test('rejects a description without an AVTransport control URL', () {
      const xml = '<root><device><friendlyName>Audio Only</friendlyName>'
          '<serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:RenderingControl:1'
          '</serviceType>'
          '<controlURL>/rendering</controlURL>'
          '</service></service></serviceList></device></root>';

      expect(
        () => UpnpDeviceDescription.parse(
          xml,
          location: Uri.parse('http://192.168.1.10/description.xml'),
        ),
        throwsA(
          isA<UpnpParseError>().having(
            (error) => error.code,
            'code',
            'DLNA_CONTROL_URL',
          ),
        ),
      );
    });
  });
}
