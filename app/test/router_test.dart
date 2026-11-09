import 'package:flutter_test/flutter_test.dart';
import 'package:sirena_hr/router.dart';

void main() {
  test('admin pages need their permission; everyday pages need none', () {
    expect(requiredPermission('/admin/employees'), 'manageEmployees');
    expect(requiredPermission('/admin/access'), 'manageAccess');
    expect(requiredPermission('/leave/approvals'), 'approveLeave');
    expect(requiredPermission('/leave'), isNull);
    expect(requiredPermission('/people/abc'), isNull);
    expect(requiredPermission('/'), isNull);
  });
}
