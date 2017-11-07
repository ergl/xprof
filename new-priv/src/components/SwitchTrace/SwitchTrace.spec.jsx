import React from 'react';
import { shallow } from 'enzyme';
import SwitchTrace from './SwitchTrace';

describe('SwitchTrace component', () => {
  const toggleTraceStatus = jest.fn();

  describe('when status running', () => {
    const props = {
      toggleTraceStatus,
      status: 'running',
    };
    const wrapper = shallow(<SwitchTrace {...props} />);

    it('renders form', () => {
      expect(wrapper.find('form').length).toBe(1);
    });
    it('outputs pause text', () => {
      expect(wrapper.find('button').text()).toEqual(' Pause Tracing');
    });
    it('outputs styled button', () => {
      expect(wrapper.find('button')).toHaveClassName('btn btn-danger');
    });
    it('outputs pause symbol', () => {
      expect(wrapper.find('span')).toHaveClassName('glyphicon glyphicon-pause');
    });
    it('invoke toggleTraceStatus on click', () => {
      wrapper.find('button').simulate('click');
      expect(toggleTraceStatus).toBeCalled();
    });
  });

  describe('when status paused', () => {
    const props = {
      toggleTraceStatus,
      status: 'paused',
    };
    const wrapper = shallow(<SwitchTrace {...props} />);

    it('outputs pause text', () => {
      expect(wrapper.find('button').text()).toEqual(' Trace All');
    });
    it('outputs styled button', () => {
      expect(wrapper.find('button')).toHaveClassName('btn btn-success');
    });
    it('outputs pause symbol', () => {
      expect(wrapper.find('span')).toHaveClassName('glyphicon glyphicon-record');
    });
  });

  describe('when status overflow', () => {
    const props = {
      toggleTraceStatus,
      status: 'overflow',
    };
    const wrapper = shallow(<SwitchTrace {...props} />);

    it('outputs pause text', () => {
      expect(wrapper.find('button').text()).toEqual(' Overflow! - resume trace all');
    });
    it('outputs styled button', () => {
      expect(wrapper.find('button')).toHaveClassName('btn btn-warning');
    });
    it('outputs pause symbol', () => {
      expect(wrapper.find('span')).toHaveClassName('glyphicon glyphicon-record');
    });
  });
});
