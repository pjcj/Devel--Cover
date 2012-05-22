package Accessor_maker;
sub import {
  no strict 'refs';
  *{ caller() . '::' . 'foo' } = sub { $_[0]->{ 'foo' } };
}
1;
